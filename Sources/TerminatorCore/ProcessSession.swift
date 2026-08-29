import Foundation

/// Идентичность отсчёта: пара `(pid, время старта процесса)`.
///
/// Один pid идентичностью не является — pid переиспользуются, и `processIdentifier`
/// документирован как изменяемый на живом объекте (findings §10). Пара с временем старта
/// различает и переиспользованный pid, и два экземпляра одного приложения, запущенных
/// через `open -n`.
public struct SessionKey: Hashable, Sendable, Comparable {

    public let pid: pid_t

    /// Время старта процесса из `p_starttime` (findings §3).
    public let startTime: Date

    public init(pid: pid_t, startTime: Date) {
        self.pid = pid
        self.startTime = startTime
    }

    /// Порядок нужен ровно затем, чтобы эффекты одного вызова `handle` шли детерминированно:
    /// сессии живут в словаре, а порядок обхода словаря в Swift не определён.
    public static func < (lhs: SessionKey, rhs: SessionKey) -> Bool {
        if lhs.pid != rhs.pid { return lhs.pid < rhs.pid }
        return lhs.startTime < rhs.startTime
    }
}

/// Почему отсчёт кончился терминальным отказом. Два случая, и они различимы **значением**,
/// а не разбором строки: поповер TASK-006 показывает пользователю две разные фразы.
public enum QuitRefusal: Equatable, Sendable {

    /// Лимит попыток исчерпан: пять отправок сделаны, каждая была принята к доставке,
    /// приложение не закрылось. Статуса отказа здесь не было вовсе — это приложение,
    /// которое держит несохранённый документ и молчит (findings §4).
    case attemptsExhausted

    /// Система отказала со статусом. Единственный статус, который терминален немедленно, —
    /// `QuitOutcome.eventNotPermitted`; остальные приводят сюда, только исчерпав лимит.
    case status(OSStatus)
}

/// Фаза одного отсчёта.
public enum SessionPhase: Equatable, Sendable {

    /// Идёт отсчёт до дедлайна.
    case counting

    /// Quit отправлен, приложение ещё живо. `attempts` — сколько отправок **сделано**
    /// (не сколько ретраев осталось): после первой отправки здесь 1, после пятой — 5.
    case awaitingQuit(attempts: Int, lastAttemptAt: Date)

    /// Терминальное состояние: больше не отправляем ничего и никогда. Состояние держится
    /// в памяти, пока процесс жив, и снимается вместе с ним.
    case refused(QuitRefusal)
}

/// Один отсчёт: один процесс, один дедлайн, одна фаза.
public struct ProcessSession: Equatable, Sendable {

    public let key: SessionKey

    /// Bundle id приложения. Точная строка, по которой сессия сопоставлена с правилом.
    public let bundleIdentifier: String

    /// Абсолютный момент истечения: `max(processStartTime, enabledAt) + limit` (DEC-001).
    /// Пересчитывается при смене лимита и никогда не накапливается сложением дельт тиков.
    public var deadline: Date

    public var phase: SessionPhase

    public init(
        key: SessionKey,
        bundleIdentifier: String,
        deadline: Date,
        phase: SessionPhase = .counting
    ) {
        self.key = key
        self.bundleIdentifier = bundleIdentifier
        self.deadline = deadline
        self.phase = phase
    }

    public var pid: pid_t { key.pid }

    public var processStartTime: Date { key.startTime }
}
