import Foundation

/// Вью-модель поповера: **чистая функция** от конфига, живых сессий, состояния карантина и
/// момента времени.
///
/// Живёт в ядре и только на Foundation — ни AppKit, ни SwiftUI, ни запущенного меню-бара для
/// её проверки не нужно. `now` приходит **параметром**, поэтому «прошло девять минут» в тесте
/// — это другой `Date`, а не sleep (findings §13).
///
/// Остаток времени здесь **пересчитывается** от абсолютного дедлайна и никогда не
/// уменьшается счётчиком: хранимое число, которое тикает таймер, разъезжается после сна
/// системы и под троттлингом, а весь движок построен ровно наоборот (findings §9).
public struct PopoverViewModel: Equatable, Sendable {

    /// Строки списка в порядке показа. **Строка = правило**, не сессия.
    public let rows: [PopoverRow]

    /// Баннер «правки не сохраняются», если хранилище в карантине. Функция состояния
    /// хранилища, а не флага, который вью ставит себе сам.
    public let banner: PopoverBanner?

    /// Пустое состояние: правил нет ни одного.
    public var isEmpty: Bool { rows.isEmpty }

    public init(
        config: RuleConfig,
        sessions: [ProcessSession],
        quarantine: ConfigLoadFailure?,
        now: Date
    ) {
        var byBundleIdentifier: [String: [ProcessSession]] = [:]
        for session in sessions {
            byBundleIdentifier[session.bundleIdentifier, default: []].append(session)
        }

        let unsorted: [PopoverRow] = config.rules.values.map { rule in
            // Внутри правила экземпляры идут по `SessionKey` — pid, затем время старта:
            // порядок обязан быть детерминирован до конца, а `activeSessions` отсортирован
            // не для показа.
            let instances = (byBundleIdentifier[rule.bundleIdentifier] ?? [])
                .sorted { $0.key < $1.key }
                .map { PopoverInstance($0, now: now) }
            return PopoverRow(
                bundleIdentifier: rule.bundleIdentifier,
                limitMinutes: rule.limit.wholeMinutes,
                isEnabled: rule.enabledAt != nil,
                instances: instances
            )
        }

        self.rows = unsorted.sorted(by: PopoverViewModel.precedes)
        self.banner = quarantine.map(PopoverBanner.init(_:))
    }

    // MARK: - Порядок строк

    /// Порядок: сначала правила с запущенными экземплярами по возрастанию **минимального**
    /// остатка, затем правила без запущенных экземпляров, затем выключенные. Ничьи — по
    /// `bundleIdentifier` по возрастанию, чтобы порядок был детерминирован.
    private static func precedes(_ lhs: PopoverRow, _ rhs: PopoverRow) -> Bool {
        if lhs.sortRank != rhs.sortRank { return lhs.sortRank < rhs.sortRank }
        if let left = lhs.soonestRemaining, let right = rhs.soonestRemaining, left != right {
            return left < right
        }
        return lhs.bundleIdentifier < rhs.bundleIdentifier
    }

    // MARK: - Остаток

    /// Остаток до дедлайна в человеческом виде.
    ///
    /// Меньше часа — `m:ss`, час и больше — `h:mm:ss`, прошедший дедлайн — `0:00`.
    /// Отрицательного значения не бывает никогда, и строка не исчезает.
    public static func remainingText(deadline: Date, now: Date) -> String {
        remainingText(seconds: remainingSeconds(deadline: deadline, now: now))
    }

    /// Остаток в секундах, никогда не отрицательный.
    public static func remainingSeconds(deadline: Date, now: Date) -> TimeInterval {
        max(0, deadline.timeIntervalSince(now))
    }

    static func remainingText(seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secondsPart = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secondsPart)
        }
        return String(format: "%d:%02d", minutes, secondsPart)
    }

    // MARK: - Редактор лимита

    /// Валидатор редактора лимита. Принимает **строку**, потому что «нецелое» выразимо
    /// только на входе редактора: при сигнатуре с `Int` нецелого ввода не бывает вовсе.
    ///
    /// Диапазон читается из `Limit.allowedMinutes` и в UI не повторяется. Ноль и
    /// отрицательное отвергаются здесь, то есть недостижимы из интерфейса, а не только на
    /// декоде файла.
    public static func limit(fromMinutesText text: String) -> LimitEditorOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let minutes = Int(trimmed) else {
            // Пусто, «12.5», «9 минут» — всё это не целое число минут.
            return .rejected(.limitIsNotWholeMinutes)
        }
        guard Limit.allowedMinutes.contains(minutes) else {
            return .rejected(.limitMinutesOutOfRange(minutes: minutes))
        }
        return .accepted(.constant(.seconds(minutes * 60)))
    }

    // MARK: - Глаза черепа

    /// Горят ли красные глаза (DEC-009).
    ///
    /// Предикат: **есть сессия в фазе `.counting` или `.awaitingQuit`**. Терминальная
    /// `.refused` красными их не делает — такая сессия живёт, пока жив процесс, и наивное
    /// `!sessions.isEmpty` держало бы глаза красными вечно. `.awaitingQuit` включена:
    /// в этой фазе движок активно шлёт quit, и потушенные глаза докладывали бы «простой»,
    /// пока продукт действует.
    public static func anyCountdownInFlight(in sessions: [ProcessSession]) -> Bool {
        sessions.contains { session in
            switch session.phase {
            case .counting, .awaitingQuit: true
            case .refused: false
            }
        }
    }
}

// MARK: - Строка

/// Одна строка списка — одно правило. У правила может не быть ни одного запущенного
/// экземпляра, а может быть несколько, и каждый несёт свой остаток: схлопывать несколько
/// дедлайнов в одно неподписанное число нельзя (findings §10).
public struct PopoverRow: Equatable, Sendable {

    /// Точная строка bundle id — она же ключ сопоставления и идентичность строки.
    public let bundleIdentifier: String

    /// Лимит в целых минутах. `nil` невыразим через конструктор правила, но тип честен.
    public let limitMinutes: Int?

    /// `enabledAt != nil` (DEC-001). Отдельного булева в модели нет.
    public let isEnabled: Bool

    /// Запущенные экземпляры в порядке `SessionKey`.
    public let instances: [PopoverInstance]

    public init(
        bundleIdentifier: String,
        limitMinutes: Int?,
        isEnabled: Bool,
        instances: [PopoverInstance]
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.limitMinutes = limitMinutes
        self.isEnabled = isEnabled
        self.instances = instances
    }

    /// Ключ сортировки: минимальный остаток среди экземпляров правила.
    public var soonestRemaining: TimeInterval? {
        instances.map(\.remaining).min()
    }

    /// Группа порядка: 0 — идут отсчёты, 1 — включено, но не запущено, 2 — выключено.
    var sortRank: Int {
        if !isEnabled { return 2 }
        return instances.isEmpty ? 1 : 0
    }
}

/// Один запущенный экземпляр приложения: свой pid, свой дедлайн, свой остаток.
public struct PopoverInstance: Equatable, Sendable {

    public let key: SessionKey

    /// Остаток в секундах на переданный момент. Никогда не отрицательный.
    public let remaining: TimeInterval

    /// Тот же остаток в виде `m:ss` или `h:mm:ss`.
    public let remainingText: String

    public let status: PopoverInstanceStatus

    public var pid: pid_t { key.pid }

    public init(_ session: ProcessSession, now: Date) {
        self.key = session.key
        self.remaining = PopoverViewModel.remainingSeconds(deadline: session.deadline, now: now)
        self.remainingText = PopoverViewModel.remainingText(seconds: self.remaining)
        self.status = PopoverInstanceStatus(session.phase)
    }
}

/// Что происходит с экземпляром прямо сейчас.
public enum PopoverInstanceStatus: Equatable, Sendable {

    /// Идёт отсчёт.
    case counting

    /// Дедлайн прошёл, quit отправлен, приложение ещё живо.
    case quitting(attempts: Int)

    /// Терминальный отказ: лестница ретраев исчерпана. Единственное состояние отказа на
    /// правило, кроме карантина, и оно обязано быть отличимо от идущего отсчёта.
    case refused(PopoverRefusal)
}

/// Почему отказ — в терминах, которые видит человек.
///
/// Ветвление по случаям `QuitRefusal` сделано здесь и только здесь. Числовое значение
/// `OSStatus` в этот тип **не проносится**: оно не показывается и ни во что не отображается.
public enum PopoverRefusal: Equatable, Sendable {

    /// Пять отправок сделаны, приложение не закрылось и молчит.
    case attemptsExhausted

    /// Система отказала. Какой именно статус — не дело пользователя и не дело этого типа.
    case systemRefused
}

extension PopoverInstanceStatus {

    init(_ phase: SessionPhase) {
        switch phase {
        case .counting:
            self = .counting
        case .awaitingQuit(let attempts, _):
            self = .quitting(attempts: attempts)
        case .refused(let refusal):
            switch refusal {
            case .attemptsExhausted: self = .refused(.attemptsExhausted)
            case .status: self = .refused(.systemRefused)
            }
        }
    }
}

// MARK: - Баннер карантина

/// Хранилище в карантине: файл на диске не трогается, прежний хороший конфиг остаётся в
/// памяти, запись отказывает. Баннер делает это явным — иначе отказ полностью бессимптомен:
/// канала уведомлений у продукта нет (DEC-004).
///
/// Строкового представления у `ConfigLoadFailure` нет ни через `CustomStringConvertible`, ни
/// через `LocalizedError`, поэтому текст пишется здесь, ветвлением по трём случаям.
public enum PopoverBanner: Equatable, Sendable {

    /// Байты на диске не разбираются.
    case unreadableConfigFile(detail: String)

    /// Файл разобрался, но правило нарушает инвариант модели.
    case rejectedRule(bundleIdentifier: String)

    /// Версия схемы из будущего: файл писала более новая сборка.
    case configFromNewerBuild(found: Int, supported: Int)

    public init(_ failure: ConfigLoadFailure) {
        switch failure {
        case .undecodableBytes(let message):
            self = .unreadableConfigFile(detail: message)
        case .rejectedRule(let rejected):
            self = .rejectedRule(bundleIdentifier: rejected.bundleIdentifier)
        case .schemaVersionFromTheFuture(let found, let supported):
            self = .configFromNewerBuild(found: found, supported: supported)
        }
    }

    /// Заголовок один на все три случая: важно не «почему», а «правки не сохраняются».
    public var title: String {
        "Rules are read-only — edits are not being saved"
    }

    public var detail: String {
        switch self {
        case .unreadableConfigFile:
            "The config file could not be read. Terminator left it untouched and is running "
                + "on the rules it had. Fix the file by hand, then reopen this popover."
        case .rejectedRule(let bundleIdentifier):
            "The rule for \(bundleIdentifier) in the config file is not valid. Terminator left "
                + "the file untouched. Fix it by hand, then reopen this popover."
        case .configFromNewerBuild(let found, let supported):
            "The config file was written by a newer build (schema \(found); this build "
                + "understands \(supported)). Terminator will not overwrite it."
        }
    }
}

// MARK: - Итог редактирования лимита

/// Результат валидации редактора лимита: либо готовый лимит, либо причина отказа из модели.
public enum LimitEditorOutcome: Equatable, Sendable {

    case accepted(Limit)
    case rejected(RuleRejectionReason)

    public var limit: Limit? {
        if case .accepted(let limit) = self { return limit }
        return nil
    }

    public var rejection: RuleRejectionReason? {
        if case .rejected(let reason) = self { return reason }
        return nil
    }
}

extension RuleRejectionReason {

    /// Текст отказа для строки в поповере.
    ///
    /// Живёт здесь, а не во вью: это представление модели, и его проверяет тест. Модель
    /// правила (TASK-003) при этом не меняется — расширение только читает её случаи.
    public var editorMessage: String {
        switch self {
        case .watchesTerminatorItself:
            "Terminator will not put a time limit on itself."
        case .limitIsNotWholeMinutes:
            "The limit must be a whole number of minutes."
        case .limitMinutesOutOfRange:
            "The limit must be between \(Limit.allowedMinutes.lowerBound) and "
                + "\(Limit.allowedMinutes.upperBound) minutes."
        }
    }
}
