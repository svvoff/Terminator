import Foundation

/// Движок наблюдения: **чистый синхронный редьюсер**.
///
/// Не `async`, не актор, без протокола `Clock` и без единого чтения реальных часов внутри:
/// момент приходит параметром `Now`, состояние меняется на месте, наружу уходит массив
/// эффектов. Из этой формы следует, что каждый сценарий проверяется юнит-тестом без sleep,
/// без `NSWorkspace` и без файловой системы (findings §13).
///
/// Три вещи, которые движок не делает никогда: не читает систему, не отправляет ничего сам
/// и не логирует напрямую. Эффекты — его единственный выход наружу.
///
/// **Ничего не накапливается.** Дедлайн — абсолютный `Date`, посчитанный один раз, и на
/// каждом тике и каждой сверке сравнивается `now.wall >= deadline`. Ни одна переменная здесь
/// не хранит «сколько прошло»: сумма дельт тиков молча превратила бы продукт в часы, идущие
/// только пока Mac не спит, — ровно та семантика, которую DEC-001 отверг (findings §9).
public struct WatchEngine {

    /// Интервал между отправками quit (DEC-002). Ретрай назревает, когда
    /// `now.wall >= lastAttemptAt + retryInterval`, и оценивается на ближайшем `.tick` или
    /// `.reconcile`, поэтому отдельный ретрай может опоздать до 5 с.
    public static let retryInterval: TimeInterval = 30

    /// Сколько отправок делается всего: на дедлайне, затем +30 с, +60 с, +90 с и +120 с.
    /// **Пять отправок за две минуты** (DEC-002). Через один интервал после последней, на
    /// +150 с, состояние становится терминальным; шестой отправки не бывает никогда.
    public static let maximumAttempts = 5

    private var config: RuleConfig

    /// Отсчёты по ключу `(pid, время старта)`. Множество процессов на один bundle id —
    /// нормальное состояние: два экземпляра одного приложения считаются независимо
    /// (findings §10).
    private var sessions: [SessionKey: ProcessSession]

    /// Bundle id, о которых уже сказано эффектом `.appFirstObserved`, чтобы он не
    /// повторялся. Он же дедуплицирует лог-событие `app-detected`.
    private var announcedBundleIdentifiers: Set<String>

    /// Сменная стратегия истечения (DEC-003). Выбирается при построении движка, в MVP
    /// реализация ровно одна.
    private let expiryAction: any ExpiryAction

    public init(config: RuleConfig = .empty, expiryAction: any ExpiryAction = QuitImmediately()) {
        self.config = config
        self.sessions = [:]
        self.announcedBundleIdentifiers = []
        self.expiryAction = expiryAction
    }

    /// Живые отсчёты в детерминированном порядке. Только чтение: состояние движка меняется
    /// исключительно через `handle(_:at:)`.
    public var activeSessions: [ProcessSession] {
        sortedKeys().compactMap { sessions[$0] }
    }

    /// Единственный вход в движок.
    public mutating func handle(_ input: EngineInput, at now: Now) -> [Effect] {
        switch input {
        case .configChanged(let config):
            return applyConfig(config)
        case .reconcile(let observed):
            return reconcile(with: observed, at: now)
        case .observed(let insertions):
            return insertions.flatMap { adopt($0, at: now) }
        case .terminated(let pid):
            return dropSessions(pid: pid, at: now)
        case .tick:
            return evaluateDeadlines(at: now)
        case .quitOutcome(let pid, let outcome):
            return apply(outcome, pid: pid, at: now)
        }
    }

    // MARK: - Конфиг

    /// Смена набора правил: пересчёт дедлайнов от **прежнего** якоря и снятие сессий
    /// выключенных правил.
    ///
    /// Истечение здесь не оценивается сознательно: укоротить лимит ниже прошедшего времени
    /// — значит просрочить сессию к ближайшему тику (DEC-001), а не в момент правки.
    ///
    /// Включение правила переякоривает, потому что оно ставит `enabledAt = now`, и та же
    /// формула `max(processStartTime, enabledAt) + limit` даёт `now + limit`. Отдельной
    /// ветки «включили» здесь нет и быть не должно — это арифметика, а не случай.
    ///
    /// Снятие сессии выключенного правила лог-событием не сопровождается: приложение не
    /// закрылось, а `app-exited` сказало бы, что закрылось. Седьмого события в списке нет.
    private mutating func applyConfig(_ newConfig: RuleConfig) -> [Effect] {
        config = newConfig
        for key in sortedKeys() {
            guard var session = sessions[key] else { continue }
            guard
                let rule = config.rule(for: session.bundleIdentifier),
                let deadline = Self.deadline(processStartTime: session.processStartTime, rule: rule)
            else {
                sessions[key] = nil
                continue
            }
            session.deadline = deadline
            sessions[key] = session
        }
        return []
    }

    // MARK: - Сверка

    /// Сверка авторитетна в обе стороны и делает три вещи в одном проходе и в этом порядке.
    ///
    /// Порядок здесь — не стиль: принятие идёт **до** оценки, поэтому процесс, просроченный
    /// ещё до того, как его увидели, закрывается на том же проходе, без grace-периода
    /// (DEC-001). Снятие идёт первым, чтобы мёртвая сессия не дожила до оценки и не получила
    /// quit на переиспользованный pid.
    private mutating func reconcile(with observed: [ObservedProcess], at now: Now) -> [Effect] {
        var effects: [Effect] = []

        // 1. Снятие. Сессия, чьей пары `(pid, время старта)` в снимке нет, удаляется и даёт
        //    `app-exited` — ровно как дало бы KVO-удаление. Это и есть восстановление после
        //    пропущенного KVO-события: без него мёртвая сессия висела бы вечно, а сессия
        //    в середине лестницы ретраев слала бы quit переиспользованному pid.
        for key in sortedKeys() where !observed.contains(where: { $0.pid == key.pid && $0.startTime == key.startTime }) {
            guard let session = sessions.removeValue(forKey: key) else { continue }
            effects.append(.log(Self.exitEvent(session, at: now)))
        }

        // 2. Принятие.
        for process in observed {
            effects.append(contentsOf: adopt(process, at: now))
        }

        // 3. Оценка дедлайнов — та же самая, что на тике. Это то, чем приложение,
        //    просрочившееся во сне Mac, закрывается на сверке после пробуждения.
        effects.append(contentsOf: evaluateDeadlines(at: now))

        return effects
    }

    /// Принятие одного процесса.
    ///
    /// Три отказа здесь **не запоминаются** и переоцениваются на следующей сверке: процесс
    /// без bundle id, процесс без времени старта и процесс, для которого правила нет или оно
    /// выключено. Множества «отвергнутых навсегда» в движке не существует.
    private mutating func adopt(_ process: ObservedProcess, at now: Now) -> [Effect] {
        // Идентичность: точное равенство строки плюс гард `.regular` (findings §10).
        // Гард живёт здесь, в редьюсере, а не в адаптере: иначе «accessory не считается»
        // нечем проверить — адаптеры юнит-тестами не покрываются.
        guard let bundleIdentifier = process.bundleIdentifier,
              process.activationPolicy == .regular,
              let rule = config.rule(for: bundleIdentifier),
              rule.enabledAt != nil
        else {
            return []
        }

        var effects: [Effect] = []

        if announcedBundleIdentifiers.insert(bundleIdentifier).inserted {
            effects.append(.appFirstObserved(bundleIdentifier: bundleIdentifier, pid: process.pid))
            effects.append(.log(LogEvent(
                kind: .appDetected,
                bundleIdentifier: bundleIdentifier,
                pid: process.pid,
                at: now.wall,
                processStartTime: process.startTime
            )))
        }

        // Времени старта нет — отсчёта нет. Откат на `Date()` здесь запрещён: он выдал бы
        // свежий полный лимит запущенным при логине приложениям (findings §3).
        guard let startTime = process.startTime else { return effects }

        let key = SessionKey(pid: process.pid, startTime: startTime)
        guard sessions[key] == nil else { return effects }
        guard let deadline = Self.deadline(processStartTime: startTime, rule: rule) else {
            return effects
        }

        sessions[key] = ProcessSession(
            key: key,
            bundleIdentifier: bundleIdentifier,
            deadline: deadline
        )
        effects.append(.log(LogEvent(
            kind: .countdownStarted,
            bundleIdentifier: bundleIdentifier,
            pid: process.pid,
            at: now.wall,
            processStartTime: startTime,
            deadline: deadline
        )))
        return effects
    }

    // MARK: - Дедлайны и лестница ретраев

    /// Оценка всех живых сессий против `now`. Один и тот же код зовут `.tick` и `.reconcile`.
    private mutating func evaluateDeadlines(at now: Now) -> [Effect] {
        var effects: [Effect] = []
        for key in sortedKeys() {
            guard let session = sessions[key] else { continue }
            switch session.phase {
            case .counting:
                guard now.wall >= session.deadline else { continue }
                effects.append(contentsOf: attemptQuit(key, at: now))

            case .awaitingQuit(let attempts, let lastAttemptAt):
                guard now.wall >= lastAttemptAt.addingTimeInterval(Self.retryInterval) else { continue }
                if attempts >= Self.maximumAttempts {
                    // Через один интервал после пятой отправки, на +150 с. Шестой нет.
                    effects.append(contentsOf: refuse(key, .attemptsExhausted, at: now))
                } else {
                    effects.append(contentsOf: attemptQuit(key, at: now))
                }

            case .refused:
                // Терминально. Сессия не ретраится больше никогда, пока жив процесс,
                // включая сверки; состояние снимается вместе с процессом.
                continue
            }
        }
        return effects
    }

    /// Одна отправка: и первая, на дедлайне, и любая из четырёх последующих.
    ///
    /// Попытка засчитывается **здесь**, в момент эмиссии эффекта, а не по приходу
    /// `.quitOutcome`. Иначе следующий тик — через 5 с, задолго до любого исхода — эмитил бы
    /// вторую отправку на ту же сессию.
    private mutating func attemptQuit(_ key: SessionKey, at now: Now) -> [Effect] {
        guard var session = sessions[key] else { return [] }

        let alreadyMade: Int
        if case .awaitingQuit(let attempts, _) = session.phase {
            alreadyMade = attempts
        } else {
            alreadyMade = 0
        }
        let number = alreadyMade + 1

        session.phase = .awaitingQuit(attempts: number, lastAttemptAt: now.wall)
        sessions[key] = session

        return [
            .log(LogEvent(
                kind: number == 1 ? .quitRequested : .quitRetry,
                bundleIdentifier: session.bundleIdentifier,
                pid: session.pid,
                at: now.wall,
                processStartTime: session.processStartTime,
                deadline: session.deadline,
                attempt: number
            )),
            // Единственная точка вызова стратегии (DEC-003): движок решил «когда»,
            // стратегия говорит «что».
            expiryAction.effect(for: session)
        ]
    }

    /// Перевод сессии в терминальное состояние.
    private mutating func refuse(_ key: SessionKey, _ refusal: QuitRefusal, at now: Now) -> [Effect] {
        guard var session = sessions[key] else { return [] }
        let attempts: Int?
        if case .awaitingQuit(let made, _) = session.phase {
            attempts = made
        } else {
            attempts = nil
        }
        session.phase = .refused(refusal)
        sessions[key] = session
        return [.log(LogEvent(
            kind: .quitRefused,
            bundleIdentifier: session.bundleIdentifier,
            pid: session.pid,
            at: now.wall,
            processStartTime: session.processStartTime,
            deadline: session.deadline,
            attempt: attempts,
            refusal: refusal
        ))]
    }

    // MARK: - Исходы и удаления

    private mutating func apply(_ outcome: QuitOutcome, pid: pid_t, at now: Now) -> [Effect] {
        var effects: [Effect] = []
        for key in sortedKeys() where key.pid == pid {
            guard let session = sessions[key] else { continue }
            switch outcome {
            case .requestSent:
                // «Принято к доставке» и ничего больше (findings §4). Попытка уже
                // посчитана, смерть придёт отдельным `.terminated(pid:)` или обнаружится
                // отсутствием в снимке сверки.
                continue

            case .notRunning:
                // Процесса нет: перепроверка `p_starttime` перед отправкой поймала либо
                // исчезновение, либо переиспользованный pid. Сессия снимается без ошибки
                // и без ретрая.
                sessions[key] = nil
                effects.append(.log(Self.exitEvent(session, at: now)))

            case .refused(let status):
                guard case .awaitingQuit = session.phase else { continue }
                if status == QuitOutcome.eventNotPermitted {
                    effects.append(contentsOf: refuse(key, .status(status), at: now))
                }
                // Любой другой статус засчитан отправкой и ретраится до лимита.
            }
        }
        return effects
    }

    /// Удаление по KVO. Это подсказка, а не наблюдение смерти: список отстаёт от ядра
    /// (findings §4). Лестница ретраев на неё ничего не ждёт — она ведётся по собственным
    /// дедлайнам движка.
    private mutating func dropSessions(pid: pid_t, at now: Now) -> [Effect] {
        var effects: [Effect] = []
        for key in sortedKeys() where key.pid == pid {
            guard let session = sessions.removeValue(forKey: key) else { continue }
            effects.append(.log(Self.exitEvent(session, at: now)))
        }
        return effects
    }

    // MARK: - Арифметика и порядок

    /// `deadline = max(processStartTime, rule.enabledAt) + rule.limit` (DEC-001).
    ///
    /// Оба операнда — `Date` на шкале стенных часов, поэтому формула не требует ни
    /// преобразования, ни второй шкалы. `enabledAt == nil` значит «правило выключено»:
    /// дедлайна нет.
    static func deadline(processStartTime: Date, rule: Rule) -> Date? {
        guard let enabledAt = rule.enabledAt else { return nil }
        return max(processStartTime, enabledAt).addingTimeInterval(rule.limit.seconds)
    }

    private static func exitEvent(_ session: ProcessSession, at now: Now) -> LogEvent {
        LogEvent(
            kind: .appExited,
            bundleIdentifier: session.bundleIdentifier,
            pid: session.pid,
            at: now.wall,
            processStartTime: session.processStartTime,
            deadline: session.deadline
        )
    }

    /// Детерминированный порядок обхода: порядок обхода словаря в Swift не определён, а
    /// порядок эффектов одного вызова `handle` проверяется тестами.
    private func sortedKeys() -> [SessionKey] {
        sessions.keys.sorted()
    }
}

extension Limit {

    /// Лимит в секундах на шкале `Date`.
    ///
    /// Доменный тип лимита — `Duration` (TASK-003), а дедлайн живёт на шкале `Date`, так что
    /// перевод нужен ровно один и он здесь. Атосекунды учтены для полноты: конструктор
    /// правила пропускает только целые минуты, так что на практике они нулевые.
    var seconds: TimeInterval {
        switch self {
        case .constant(let value):
            let parts = value.components
            return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
        }
    }
}
