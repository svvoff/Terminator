import Foundation

/// Почему файл фокуса не удалось прочитать. Читаемое состояние карантина хранилища.
///
/// Причин две, и различаются они сопоставлением значений, а не текста. Отказ должен быть
/// симптомен: у продукта нет канала уведомлений (DEC-004), а данные фокуса — единственное
/// будущее доказательство для пересмотра DEC-008, и молча потерять их нельзя.
public enum FocusLoadFailure: Error, Equatable, Sendable {

    /// Байты на диске не разбираются как свёртка текущей версии схемы.
    case undecodableBytes(message: String)

    /// Версия схемы в файле больше поддерживаемой: файл писала более новая сборка.
    /// Старая сборка не смеет его затирать.
    case schemaVersionFromTheFuture(found: Int, supported: Int)
}

// MARK: - Формат на диске

/// Корневой объект файла фокуса.
///
/// Файл **свой**, отдельный от файла правил, и это не вкусовщина: слив фокуса идёт каждую
/// минуту, а правила — единственная копия того, что пользователь настроил руками. Один файл
/// на двоих означал бы, что минутный писатель регулярно переписывает правила.
private struct FocusDTO: Codable {
    var schemaVersion: Int

    /// День (`"2026-08-29"`) → bundle id → **целые секунды**.
    ///
    /// Секунды целым числом, а не `Duration`: доменная длительность кодируется в непрозрачный
    /// массив из двух чисел, который нельзя ни прочитать глазами, ни поправить руками
    /// (findings §11). Субсекундный остаток живёт в памяти накопителя и на диск не попадает.
    var days: [String: [String: Int]]
}

// MARK: - Кодек

/// Границы формата файла фокуса: байты ↔ дневная свёртка.
enum FocusFormat {

    /// Версия схемы, которую эта сборка пишет и умеет читать.
    static let currentSchemaVersion = 1

    /// Кодирует свёртку в байты файла.
    ///
    /// Pretty-printed и с сортировкой ключей, по образцу файла правил: файл читается глазами,
    /// а строковая сортировка ключей вида `2026-08-29` совпадает с хронологической, так что
    /// дни идут сверху вниз по времени.
    static func encode(_ rollup: FocusRollup) throws -> Data {
        var stored: [String: [String: Int]] = [:]
        for (day, apps) in rollup.days {
            var perApp: [String: Int] = [:]
            for (bundleIdentifier, duration) in apps {
                let seconds = Int(duration.components.seconds)
                // Ноль секунд записью не является: дробь меньше секунды остаётся в памяти
                // накопителя и попадёт в файл, когда наберётся до целой.
                guard seconds > 0 else { continue }
                perApp[bundleIdentifier] = seconds
            }
            guard !perApp.isEmpty else { continue }
            stored[day.description] = perApp
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(FocusDTO(schemaVersion: currentSchemaVersion, days: stored))
    }

    /// Разбирает байты файла в свёртку.
    ///
    /// Любой отказ — карантин: ни одна ветка ничего не чинит и ничего не отбрасывает. Историю
    /// нельзя восполнить задним числом (DEC-005), поэтому непонятный файл остаётся на диске
    /// байт в байт, а сливы отказывают.
    static func decode(_ data: Data) throws -> FocusRollup {
        let stored: FocusDTO
        do {
            stored = try JSONDecoder().decode(FocusDTO.self, from: data)
        } catch {
            throw FocusLoadFailure.undecodableBytes(message: String(describing: error))
        }

        guard stored.schemaVersion <= currentSchemaVersion else {
            throw FocusLoadFailure.schemaVersionFromTheFuture(
                found: stored.schemaVersion,
                supported: currentSchemaVersion
            )
        }
        guard stored.schemaVersion == currentSchemaVersion else {
            throw FocusLoadFailure.undecodableBytes(
                message: "schemaVersion \(stored.schemaVersion) never existed; "
                    + "this build reads version \(currentSchemaVersion)"
            )
        }

        var rollup = FocusRollup()
        for (text, apps) in stored.days {
            guard let day = DayKey(text: text) else {
                throw FocusLoadFailure.undecodableBytes(message: "day key \(text) is not YYYY-MM-DD")
            }
            for (bundleIdentifier, seconds) in apps {
                guard seconds >= 0 else {
                    throw FocusLoadFailure.undecodableBytes(
                        message: "negative seconds \(seconds) for \(bundleIdentifier) on \(text)"
                    )
                }
                rollup.add(.seconds(seconds), to: bundleIdentifier, on: day)
            }
        }
        return rollup
    }
}
