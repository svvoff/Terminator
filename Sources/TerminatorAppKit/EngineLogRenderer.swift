import Foundation
import os

import TerminatorCore

/// Один формат отметки времени на все лог-строки продукта: ISO 8601 с долями секунды, UTC.
///
/// Доли важны: ручной чеклист сравнивает отметки `countdown-started` и `quit-requested` и
/// смотрит, укладывается ли перелёт дедлайна в один тик.
///
/// Стиль форматирования — value type и `Sendable`, поэтому им пользуется и отправитель quit
/// с фонового потока. `ISO8601DateFormatter` — класс, и общий экземпляр между потоками здесь
/// был бы не нужным риском.
nonisolated let logStampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

nonisolated func logStamp(_ date: Date?) -> String {
    guard let date else { return "-" }
    return logStampStyle.format(date)
}

/// Рендерер диагностических событий движка.
///
/// Движок сам не логирует ничего: он эмитит `.log(LogEvent)`, а строку пишет этот тип. Лог —
/// **весь** ответ на вопрос «почему оно закрылось»: перед закрытием приложения не бывает ни
/// предупреждения, ни уведомления, ни звука (DEC-004, findings §14).
///
/// Формат строки один на все шесть событий, и это сознательно: единая форма читается грепом,
/// а `privacy: .public` на каждой интерполяции проверяется глазами в одном месте, а не в
/// шести. Отсутствующее поле печатается как `-`.
///
/// Читается дословно этой командой:
///
///     log show --predicate 'subsystem == "com.svvoff.terminator"' --style compact --last 1h
public struct EngineLogRenderer: Sendable {

    public init() {}

    public func render(_ event: LogEvent) {
        engineLog.notice("\(event.kind.rawValue, privacy: .public) bundleID=\(event.bundleIdentifier, privacy: .public) pid=\(event.pid, privacy: .public) at=\(logStamp(event.at), privacy: .public) start=\(logStamp(event.processStartTime), privacy: .public) deadline=\(logStamp(event.deadline), privacy: .public) attempt=\(Self.describe(event.attempt), privacy: .public) refusal=\(Self.describe(event.refusal), privacy: .public)")
    }

    private static func describe(_ attempt: Int?) -> String {
        guard let attempt else { return "-" }
        return "\(attempt)/\(WatchEngine.maximumAttempts)"
    }

    private static func describe(_ refusal: QuitRefusal?) -> String {
        switch refusal {
        case nil: "-"
        case .attemptsExhausted: "attempts-exhausted"
        case .status(let status): "status=\(status)"
        }
    }
}
