import Foundation
import os

/// Почему конфиг не удалось загрузить. Читаемое состояние карантина хранилища.
///
/// Три причины, и они различаются сопоставлением значений, а не текста: баннер TASK-006 и
/// тест смотрят на case. Без такого свойства отказ был бы полностью бессимптомным —
/// продукт не имеет канала уведомлений (DEC-004), пользователь правил бы правила, а они
/// молча не сохранялись бы.
public enum ConfigLoadFailure: Error, Equatable, Sendable {

    /// Байты на диске не разбираются как конфиг текущей версии схемы.
    /// `message` несёт текст ошибки декода — он идёт в лог и в баннер.
    case undecodableBytes(message: String)

    /// Синтаксически файл разобрался, но правило нарушает инвариант модели.
    /// Файл не чинится и частично не грузится: правку делал человек, чинит её тоже человек.
    case rejectedRule(RuleRejected)

    /// Версия схемы в файле больше поддерживаемой: файл писала более новая сборка.
    /// Старая сборка не смеет его затирать.
    case schemaVersionFromTheFuture(found: Int, supported: Int)
}

// MARK: - Формат на диске

/// Корневой объект файла.
///
/// Формат отделён от доменных типов намеренно: домен волен меняться без смены файла, файл —
/// без смены домена. Это единственное место, где живёт форма JSON.
private struct ConfigDTO: Codable {
    var schemaVersion: Int
    var rules: [String: RuleDTO]
}

/// Правило на диске. Идентификатор приложения — не поле, а **ключ** в `rules`, поэтому
/// два правила на одно приложение невозможны по форме файла, а не по проверке.
private struct RuleDTO: Codable {

    /// Отсутствует или null — правило выключено (DEC-001). Отдельного булева флага нет.
    var enabledAt: Date?

    var limit: LimitDTO
}

/// Лимит на диске: тегированный объект, а не голое число.
///
/// Тег `kind` есть с первого записанного байта, чтобы Stage 3 добавляла вид лимита
/// расширением формата, а не миграцией. Сейчас вид ровно один.
///
/// Длительность пишется целыми секундами. Доменный тип длительности на диск не попадает
/// ни на каком уровне вложенности: он кодируется в непрозрачный массив из двух целых
/// (findings §11), который нельзя ни прочитать глазами, ни поправить руками.
private struct LimitDTO: Codable {

    enum Kind: String, Codable {
        case constant
    }

    var kind: Kind

    /// Кратно 60, от 60 до 28800 включительно — то же, что 1…480 целых минут.
    var limitSeconds: Int
}

// MARK: - Кодек

/// Границы формата: байты ↔ доменный конфиг. Больше никто в продукте не знает, как выглядит
/// файл.
enum ConfigFormat {

    /// Версия схемы, которую эта сборка пишет и умеет читать. Ровно одна: машинерии миграций
    /// нет, мигратор v1 → v2 пишется тогда, когда появится v2.
    static let currentSchemaVersion = 1

    /// Кодирует конфиг в байты файла.
    ///
    /// Pretty-printed и с сортировкой ключей: файл правится руками, поэтому диффы должны быть
    /// маленькими, а повторная запись одного и того же конфига — побайтово одинаковой.
    /// Даты — ISO 8601 без долей секунды: `"2026-08-27T13:00:00Z"` читается и набирается
    /// руками, отсчёт всё равно идёт минутами.
    static func encode(_ config: RuleConfig) throws -> Data {
        var stored: [String: RuleDTO] = [:]
        for (identifier, rule) in config.rules {
            stored[identifier] = RuleDTO(
                enabledAt: rule.enabledAt,
                limit: LimitDTO(kind: .constant, limitSeconds: seconds(of: rule.limit))
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(ConfigDTO(schemaVersion: currentSchemaVersion, rules: stored))
    }

    /// Разбирает байты файла в доменный конфиг.
    ///
    /// Неизвестные ключи внутри известной версии схемы игнорируются. Любой отказ — это
    /// `ConfigLoadFailure`, то есть карантин: ни одна ветка здесь ничего не чинит и ничего
    /// не отбрасывает, потому что файл — единственная копия правил пользователя.
    static func decode(_ data: Data) throws -> RuleConfig {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let stored: ConfigDTO
        do {
            stored = try decoder.decode(ConfigDTO.self, from: data)
        } catch {
            throw ConfigLoadFailure.undecodableBytes(message: String(describing: error))
        }

        guard stored.schemaVersion <= currentSchemaVersion else {
            throw ConfigLoadFailure.schemaVersionFromTheFuture(
                found: stored.schemaVersion,
                supported: currentSchemaVersion
            )
        }
        guard stored.schemaVersion == currentSchemaVersion else {
            throw ConfigLoadFailure.undecodableBytes(
                message: "schemaVersion \(stored.schemaVersion) never existed; "
                    + "this build reads version \(currentSchemaVersion)"
            )
        }

        var config = RuleConfig()
        var rejections: [RuleRejected] = []

        // Порядок обхода фиксирован, чтобы «первое отвергнутое правило» не зависело от
        // порядка обхода словаря: пользователь должен получать один и тот же ответ на один
        // и тот же файл.
        for (identifier, entry) in stored.rules.sorted(by: { $0.key < $1.key }) {
            do {
                let rule = try Rule(
                    bundleIdentifier: identifier,
                    limit: .constant(.seconds(entry.limit.limitSeconds)),
                    enabledAt: entry.enabledAt
                )
                config.set(rule)
            } catch let rejected as RuleRejected {
                let reason = String(describing: rejected.reason)
                storeLog.notice("rule rejected on decode: bundle=\(rejected.bundleIdentifier, privacy: .public) limitSeconds=\(entry.limit.limitSeconds, privacy: .public) reason=\(reason, privacy: .public)")
                rejections.append(rejected)
            } catch {
                throw ConfigLoadFailure.undecodableBytes(message: String(describing: error))
            }
        }

        if let first = rejections.first {
            throw ConfigLoadFailure.rejectedRule(first)
        }
        return config
    }

    /// Целые секунды лимита для записи на диск.
    private static func seconds(of limit: Limit) -> Int {
        switch limit {
        case .constant(let value):
            return Int(value.components.seconds)
        }
    }
}
