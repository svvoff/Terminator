import Foundation

/// Лимит правила.
///
/// Один enum, один case, одно ассоциированное значение. Тегированное представление, а не
/// голое число, потому что Stage 3 добавит второй вид лимита (расписание) — и тогда это
/// будет расширение формата, а не миграция. До тех пор второго case нет, протокола
/// стратегии нет, резолвера нет: в MVP лимит ровно один и он постоянный.
///
/// Доменный тип — `Duration`. Границу диска он не пересекает никогда: в JSON пишется
/// `limitSeconds: Int` (findings §11).
public enum Limit: Equatable, Sendable {
    case constant(Duration)
}

extension Limit {

    /// Допустимый лимит — целое число минут от 1 до 480 включительно.
    ///
    /// Диапазон не бесконечен с обеих сторон осознанно: ноль и отрицательное значение
    /// означали бы «закрывать немедленно и всегда», а верхняя граница в восемь часов
    /// отделяет опечатку от намерения. Тот же диапазон проверяет редактор TASK-006.
    public static let allowedMinutes = 1...480

    /// Лимит в целых минутах, либо nil, если он не выражается целым числом минут.
    ///
    /// Дробная доля секунды тоже даёт nil: `Duration` умеет аттосекунды, а правило — нет.
    public var wholeMinutes: Int? {
        switch self {
        case .constant(let value):
            let parts = value.components
            guard parts.attoseconds == 0, parts.seconds % 60 == 0 else { return nil }
            return Int(parts.seconds / 60)
        }
    }
}

/// Почему правило отвергнуто. Причины различимы сопоставлением значений, не текста:
/// баннер TASK-006 и тест одинаково смотрят на case, а не на строку.
public enum RuleRejectionReason: Equatable, Sendable {

    /// Правило смотрит за самим Terminator. Через UI недостижимо, но файл правится руками.
    case watchesTerminatorItself

    /// Лимит не выражается целым числом минут (например 90 секунд).
    case limitIsNotWholeMinutes

    /// Лимит выражается целыми минутами, но вне `Limit.allowedMinutes`.
    case limitMinutesOutOfRange(minutes: Int)
}

/// Отказ в построении правила: какое правило и почему.
public struct RuleRejected: Error, Equatable, Sendable {

    public let bundleIdentifier: String
    public let reason: RuleRejectionReason

    public init(bundleIdentifier: String, reason: RuleRejectionReason) {
        self.bundleIdentifier = bundleIdentifier
        self.reason = reason
    }
}

/// Правило наблюдения за одним приложением.
///
/// `enabledAt` — одновременно флаг включённости и якорь отсчёта (DEC-001): `nil` значит
/// «выключено». Отдельного булева `isEnabled` нет ни здесь, ни на диске, поэтому состояние
/// «включено, но без якоря» невыразимо по построению.
///
/// Дедлайн здесь не считается: `max(processStartTime, enabledAt) + limit` — предмет
/// TASK-004. Эта карточка `enabledAt` только хранит.
public struct Rule: Equatable, Sendable {

    /// Точная строка bundle id приложения-цели. Сопоставление — только полное равенство:
    /// `hasPrefix` затянул бы Electron-хелперы (findings §10).
    public let bundleIdentifier: String

    public let limit: Limit

    /// Момент включения правила, он же якорь отсчёта. `nil` — правило выключено.
    public let enabledAt: Date?

    /// Единственный конструктор правила, и он проверяет оба инварианта модели.
    ///
    /// Инварианты проверяются здесь, а не в UI, потому что конфиг правится руками: модель —
    /// последняя линия, и декод конфига проходит ровно через этот же конструктор.
    public init(bundleIdentifier: String, limit: Limit, enabledAt: Date? = nil) throws {
        guard bundleIdentifier != TerminatorIdentity.bundleIdentifier else {
            throw RuleRejected(bundleIdentifier: bundleIdentifier, reason: .watchesTerminatorItself)
        }
        guard let minutes = limit.wholeMinutes else {
            throw RuleRejected(bundleIdentifier: bundleIdentifier, reason: .limitIsNotWholeMinutes)
        }
        guard Limit.allowedMinutes.contains(minutes) else {
            throw RuleRejected(
                bundleIdentifier: bundleIdentifier,
                reason: .limitMinutesOutOfRange(minutes: minutes)
            )
        }
        self.bundleIdentifier = bundleIdentifier
        self.limit = limit
        self.enabledAt = enabledAt
    }
}
