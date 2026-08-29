import Foundation

/// Диагностическое событие движка. Рендерит его адаптер; ядро само не логирует ничего.
///
/// Перед закрытием приложения не бывает ни предупреждения, ни уведомления, ни звука
/// (DEC-004), поэтому лог — **весь** ответ на вопрос «почему оно закрылось» (findings §14).
/// Событий ровно шесть, список закрытый.
public struct LogEvent: Equatable, Sendable {

    /// Имена событий — те же строки, что уходят в `os.Logger` и что человек ищет в выводе
    /// `log show`. Поэтому это `rawValue`, а не производная от имени case.
    public enum Kind: String, Equatable, Sendable {

        /// Наблюдаемое приложение впервые увидено запущенным в этом процессе Terminator.
        /// Событие про **bundle id**, а не про сессию: второй экземпляр того же приложения
        /// его не повторяет. Оно же — единственная строка, которая появится для процесса,
        /// у которого не удалось прочитать время старта: `app-detected` без
        /// `countdown-started` читается как «увидели, но не считаем».
        case appDetected = "app-detected"

        /// Отсчёт начат: у сессии есть якорь и дедлайн.
        case countdownStarted = "countdown-started"

        /// Первая отправка quit, на дедлайне.
        case quitRequested = "quit-requested"

        /// Повторная отправка: вторая, третья, четвёртая или пятая.
        case quitRetry = "quit-retry"

        /// Терминальный отказ: либо исчерпаны пять отправок, либо система отказала
        /// статусом, который терминален немедленно.
        case quitRefused = "quit-refused"

        /// Процесс исчез: по KVO-удалению, по отсутствию в снимке сверки или по
        /// `.notRunning` от отправителя.
        case appExited = "app-exited"
    }

    public let kind: Kind

    public let bundleIdentifier: String

    public let pid: pid_t

    /// Момент события по стенным часам — тот самый `Now.wall`, с которым звали редьюсер.
    public let at: Date

    /// Время старта процесса. nil там, где сессии ещё нет (`app-detected` для процесса без
    /// прочитанного `p_starttime`).
    public let processStartTime: Date?

    /// Дедлайн сессии, если он посчитан.
    public let deadline: Date?

    /// Номер отправки: 1 для первой, 5 для последней.
    public let attempt: Int?

    /// Причина терминального отказа — только у `quit-refused`.
    public let refusal: QuitRefusal?

    public init(
        kind: Kind,
        bundleIdentifier: String,
        pid: pid_t,
        at: Date,
        processStartTime: Date? = nil,
        deadline: Date? = nil,
        attempt: Int? = nil,
        refusal: QuitRefusal? = nil
    ) {
        self.kind = kind
        self.bundleIdentifier = bundleIdentifier
        self.pid = pid
        self.at = at
        self.processStartTime = processStartTime
        self.deadline = deadline
        self.attempt = attempt
        self.refusal = refusal
    }
}

/// Всё, что движок сообщает наружу. Эффекты — его единственный выход: он ничего не читает
/// из системы, ничего не отправляет и не логирует напрямую.
public enum Effect: Equatable, Sendable {

    /// Отправить вежливый quit этой сессии. Адаптер перепроверяет `p_starttime`
    /// непосредственно перед отправкой и возвращает исход входом `.quitOutcome`.
    case requestQuit(ProcessSession)

    /// Диагностическая строка для рендерера лога.
    case log(LogEvent)

    /// Наблюдаемый bundle id впервые увиден запущенным в этом процессе Terminator —
    /// один раз на идентификатор, а не на сессию: два экземпляра одного приложения дают
    /// один эффект.
    ///
    /// **Потребителя у эффекта нет.** TASK-005 (прогрев согласия) была единственным
    /// потребителем и отложена 2026-08-28: quit не спрашивает согласия вовсе, греть нечего
    /// (findings §5). Эффект остаётся честной констатацией факта, который движок знает:
    /// он стоит один case и один тест, а подключать его в этой задаче не к чему.
    case appFirstObserved(bundleIdentifier: String, pid: pid_t)
}
