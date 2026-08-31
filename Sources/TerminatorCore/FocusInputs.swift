import Foundation

/// Приложение, ставшее фронтмост, в том виде, в каком его видит адаптер.
///
/// Наблюдатель подписан **системно** и не сужен до наблюдаемых bundle id: сужённая подписка
/// не увидела бы приложения, против которого надо закрыть текущий спан (DEC-005). Фильтрует
/// движок, а не адаптер, — по той же причине, по которой гард `.regular` живёт в редьюсере:
/// адаптеры юнит-тестами не покрываются вовсе.
///
/// Опциональность двух полей — смысловая, ровно как у `ObservedProcess`:
///
/// - `bundleIdentifier == nil` — процесс без идентификатора: спан для него не открывается,
///   но текущий спан он закрывает, потому что фокус ушёл;
/// - `startTime == nil` — `p_starttime` не прочитан. Спан открывается, но без `SessionKey`:
///   сливать его по удалению сессии будет нечему, и он закроется ближайшей сменой фокуса.
public struct FrontmostApp: Equatable, Sendable {

    /// Идентификатор процесса. Идентичностью сам по себе не является (findings §10) — см.
    /// `sessionKey`.
    public let pid: pid_t

    /// Точная строка bundle id. Сопоставление с правилом — только полное равенство.
    public let bundleIdentifier: String?

    /// Время старта процесса из `p_starttime` (findings §3). Нужно затем, чтобы открытый спан
    /// держал `SessionKey`, а не голый pid: инвариант порядка формулируется в терминах
    /// таблицы сессий, а её ключ — пара `(pid, время старта)`.
    public let startTime: Date?

    public let activationPolicy: ProcessActivationPolicy

    public init(
        pid: pid_t,
        bundleIdentifier: String?,
        startTime: Date?,
        activationPolicy: ProcessActivationPolicy
    ) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.startTime = startTime
        self.activationPolicy = activationPolicy
    }

    /// Ключ сессии этого процесса, если время старта прочитано.
    public var sessionKey: SessionKey? {
        startTime.map { SessionKey(pid: pid, startTime: $0) }
    }
}

/// Почему накопление фокуса приостановлено.
///
/// Четыре причины, список закрытый (DEC-005). Каждая — однозначная наблюдаемая смена
/// состояния без единого настраиваемого числа: машина спит или нет, экран заперт или нет.
/// Порог HID-простоя сюда не входит и не входил: он требует выбрать N, а любое N меняет
/// смысл записанных чисел (`TASK-106`).
///
/// Причины держатся **множеством**, а не флагом: засыпание Mac поднимает сон дисплея и сон
/// системы вместе, блокировка экрана накладывается на любое из них. Одинокий булев флаг
/// выглядит эквивалентом и им не является — первое же возобновление сняло бы паузу, пока
/// машина ещё спит.
public enum FocusPauseReason: String, Equatable, Hashable, Sendable, CaseIterable {

    /// Сон системы.
    case systemSleep = "system-sleep"

    /// Сон дисплея.
    case displaySleep = "display-sleep"

    /// Блокировка экрана или скринсейвер.
    case screenLocked = "screen-locked"

    /// Переключение пользователя: сессия перестала быть активной.
    case sessionResignedActive = "session-resigned-active"
}
