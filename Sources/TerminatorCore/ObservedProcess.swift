import Foundation

/// Политика активации процесса — ровно столько, сколько ядру нужно знать о ней.
///
/// Тип свой, а не `NSApplication.ActivationPolicy`: `TerminatorCore` — только Foundation,
/// AppKit сюда не попадает (findings §13). Значения повторяют системный enum один в один,
/// перевод делает адаптер.
///
/// Зачем это вообще в ядре: гард «только `.regular`» — часть сопоставления правила
/// (findings §10), и он живёт в редьюсере, а не в адаптере. Отфильтруй адаптер
/// не-`.regular` процессы у себя — и правило «accessory-приложение не считается» стало бы
/// непроверяемым юнит-тестом, потому что адаптеры юнит-тестами не покрываются вовсе.
public enum ProcessActivationPolicy: Equatable, Sendable {

    /// Обычное приложение с доком и меню. Таких ~11 из ~90 процессов (findings §10).
    case regular

    /// `LSUIElement`: живёт в меню-баре, дока нет.
    case accessory

    /// `LSBackgroundOnly`: интерфейса нет вовсе.
    case prohibited
}

/// Один наблюдаемый процесс в том виде, в каком его видит адаптер.
///
/// Опциональность двух полей — смысловая, а не для удобства вызова:
///
/// - `bundleIdentifier == nil` — процесс без идентификатора (пять из ~90, findings §10).
///   Он игнорируется **на этот проход** и переоценивается на следующей сверке: в множество
///   «отвергнутых навсегда» он не попадает никогда;
/// - `startTime == nil` — `p_starttime` не удалось прочитать. Отсчёт не начинается, но
///   процесс так же переоценивается на следующей сверке. Откат на `Date()` здесь
///   запрещён: он молча выдал бы свежий полный лимит ровно тем запущенным при логине
///   приложениям, ради которых продукт существует (findings §3).
public struct ObservedProcess: Equatable, Sendable {

    /// Идентификатор процесса. Идентичностью **сам по себе** он не является: pid
    /// переиспользуются, а `processIdentifier` документирован как изменяемый на живом
    /// объекте (findings §10). Идентичность — пара `(pid, startTime)`, см. `SessionKey`.
    public let pid: pid_t

    /// Bundle id приложения, если он есть. Сопоставление с правилом — только полное
    /// равенство строки: `hasPrefix` затянул бы Chromium-рендереры (findings §10).
    public let bundleIdentifier: String?

    /// Время старта процесса на шкале стенных часов, из `p_starttime` (findings §3).
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
}
