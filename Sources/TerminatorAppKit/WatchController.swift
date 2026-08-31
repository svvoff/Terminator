import AppKit
import Foundation

import TerminatorCore

/// Проводка движка: всё, что трогает систему, и ничего, что решает.
///
/// Контроллер владеет движком, хранилищем, KVO-наблюдателем, двумя таймерами, отправителем
/// quit и рендерером лога. Решений он не принимает вовсе: переводит мир во входы, отдаёт их
/// редьюсеру и исполняет эффекты.
///
/// **Два таймера, а не один.** Тик — 5 с, это чистый вызов редьюсера, который ничего не
/// читает. Сверка — 30 с, она снимает `runningApplications` и читает `p_starttime` на каждый
/// процесс. Один 30-секундный таймер на оба сделал бы худший перелёт дедлайна
/// 30-секундным вместо 5-секундного.
///
/// Пунктуальность обоих таймеров не является основанием ни для чего: `Timer` живёт на
/// suspending-семье часов, которая останавливается во сне системы, и на машине автора две
/// семьи разошлись на 42 часа (findings §9). Основание истечения — пересчёт абсолютных
/// `Date`-дедлайнов на каждом тике и каждой сверке. Ассертов активности не берётся:
/// `NSActivityUserInitiated` буквально включает `NSActivityIdleSystemSleepDisabled`, то есть
/// запретил бы Mac засыпать, пока работает хоть одно наблюдаемое приложение.
public final class WatchController {

    private var engine: WatchEngine
    private let store: ConfigStore
    private let observer: RunningApplicationsObserver
    private let sender: QuitSender
    private let logRenderer: EngineLogRenderer

    /// Хранилище дневной свёртки фокуса (TASK-007). Каталог тот же, что у правил, файл —
    /// свой: минутный слив фокуса не имеет права переписывать правила пользователя.
    private let focusStore: FocusStore

    /// Наблюдатель фокуса: KVO по фронтмосту, четыре сигнала паузы, смена дня.
    private let focusObserver: FrontmostFocusObserver

    private var tickTimer: Timer?
    private var sweepTimer: Timer?
    private var flushTimer: Timer?
    private var notificationTokens: [any NSObjectProtocol] = []

    /// Свёртка, записанная последним успешным сливом. Слив пропускается, пока она не
    /// изменилась: «грязно» — это ровно «свёртка отличается от записанной».
    ///
    /// Начальное значение — пустая свёртка, а не nil: запуск, в котором ни одно наблюдаемое
    /// приложение не побывало фронтмост, не должен создавать файл из ничего.
    private var lastFlushed: FocusRollup = .empty

    /// Каденция тика: дедлайн соблюдается в пределах одного тика, худший перелёт — 5 с.
    public static let tickInterval: TimeInterval = 5

    /// Каденция полной сверки.
    public static let sweepInterval: TimeInterval = 30

    /// Каденция слива фокуса: не чаще раза в минуту, пока свёртка грязная. Полная запись с
    /// fsync месяца данных — ~7 мс при ~10 КБ (findings §11), так что каденция выбрана ради
    /// опрятности, а не ради цены.
    public static let flushInterval: TimeInterval = 60

    /// Состояние движка изменилось: любой вход прошёл через `dispatch(_:)`, эффекты
    /// исполнены. Полезной нагрузки нет намеренно — вызывающий перечитывает
    /// `activeSessions` сам, поэтому колбэк остаётся одной строкой в одной точке.
    ///
    /// Форма та же, что у `RunningApplicationsObserver.start(onInsertions:onRemovals:)`:
    /// в дереве нет ни `@Observable`, ни `ObservableObject`, и заводить их ради одного
    /// бита незачем.
    public var onStateChanged: (() -> Void)?

    /// Живые отсчёты движка — **только чтение**. Единственный источник данных для живого
    /// отсчёта в поповере и для состояния глаз глифа.
    ///
    /// Порядок здесь — по ключу сессии (pid, затем время старта), а не порядок показа:
    /// сортировку для списка делает вью-модель.
    public var activeSessions: [ProcessSession] { engine.activeSessions }

    /// Живой конфиг хранилища — проброс, только чтение.
    public var config: RuleConfig { store.config }

    /// Причина карантина хранилища, либо nil. Поповер рисует по ней баннер.
    public var quarantine: ConfigLoadFailure? { store.quarantine }

    /// Дневная свёртка фокуса по состоянию на сейчас — **только чтение**, проброс движка по
    /// образцу `activeSessions`. Потребитель в MVP один: слив на диск.
    public var focusRollup: FocusRollup { engine.focusRollup(at: currentNow) }

    public init(
        store: ConfigStore,
        expiryAction: any ExpiryAction = QuitImmediately(),
        observer: RunningApplicationsObserver = RunningApplicationsObserver(),
        sender: QuitSender = QuitSender(),
        logRenderer: EngineLogRenderer = EngineLogRenderer(),
        focusObserver: FrontmostFocusObserver = FrontmostFocusObserver()
    ) {
        self.store = store
        self.engine = WatchEngine(expiryAction: expiryAction)
        self.observer = observer
        self.sender = sender
        self.logRenderer = logRenderer
        self.focusObserver = focusObserver
        // Каталог берётся у хранилища правил, а не у константы: подменённый каталог правил
        // обязан уводить за собой и файл фокуса, иначе тест или запуск с временным каталогом
        // писал бы в настоящий `~/Library/Application Support`.
        self.focusStore = FocusStore(dataDirectory: store.dataDirectory)
    }

    /// Запуск графа: конфиг, наблюдение, таймеры, пробуждение — и сверка.
    ///
    /// Последним шагом идёт `reconcile()`, и это **та же самая функция**, которую зовут
    /// таймер, пробуждение и активация сессии. Отдельного кода принятия на старте не
    /// существует: холодный путь обязан прогоняться каждые 30 с, иначе баг в нём не
    /// находится.
    public func start() {
        store.load()
        dispatch(.configChanged(store.config))

        // Чтение файла фокуса — не восполнение истории, а условие её сохранности: движок
        // стартует пустым, и слив без прочитанного прошлого стёр бы все записанные дни.
        focusStore.load()
        focusLog.notice("focus store loaded: path=\(self.focusStore.focusURL.path, privacy: .public) days=\(self.focusStore.recorded.days.count, privacy: .public) quarantine=\(String(describing: self.focusStore.quarantine), privacy: .public)")

        observer.start(
            onInsertions: { [weak self] insertions in
                self?.dispatch(.observed(insertions: insertions))
            },
            onRemovals: { [weak self] pids in
                for pid in pids { self?.dispatch(.terminated(pid: pid)) }
            }
        )

        tickTimer = Timer.scheduledTimer(
            withTimeInterval: Self.tickInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dispatch(.tick) }
        }

        sweepTimer = Timer.scheduledTimer(
            withTimeInterval: Self.sweepInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }

        // Входы фокуса идут той же воронкой `dispatch(_:)`, что и остальные: второй воронки
        // в контроллере нет. Смена дня — единственный момент, когда слив идёт вне каденции:
        // вчерашний день закрыт, и держать его только в памяти незачем.
        focusObserver.start { [weak self] input in
            guard let self else { return }
            self.dispatch(input)
            if case .dayRollover = input { self.flushFocus() }
        }

        flushTimer = Timer.scheduledTimer(
            withTimeInterval: Self.flushInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushFocus() }
        }

        // Пробуждение и активация сессии — не входы движка. Адаптер превращает их в
        // немедленную сверку, ту же самую.
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            let token = NSWorkspace.shared.notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reconcile() }
            }
            notificationTokens.append(token)
        }

        reconcile()
    }

    /// **Единственная функция сверки.** Её зовут бутстрап, 30-секундный таймер, пробуждение
    /// и активация сессии. Второй такой функции в продукте нет.
    public func reconcile() {
        dispatch(.reconcile(observed: NSWorkspace.shared.runningApplications.map(observedProcess(from:))))
    }

    /// **Единственная дверь для правки конфига.** Три вещи по порядку: долговечная запись,
    /// уведомление движка, сверка.
    ///
    /// Хранилище наружу не отдаётся сознательно: с ним в руках UI мог бы позвать
    /// `save(_:)` и забыть сказать движку — и тогда файл записан, список обновлён,
    /// пользователь видит выключенное правило, а отсчёт идёт и приложение будет закрыто.
    /// Отказ был бы полностью бессимптомным, а канала уведомлений у продукта нет (DEC-004).
    ///
    /// Уведомление и сверка идут **только при успехе**: в карантине `save` бросает, ни байта
    /// не пишет, и движок обязан остаться на прежнем — записанном на диске — наборе правил.
    ///
    /// Почему в конце `reconcile()`: `applyConfig` в редьюсере обходит только уже
    /// существующие сессии и не заводит новых. Без сверки включение правила для **уже
    /// запущенного** приложения не дало бы отсчёта до ближайшей сверки, до 30 с, тогда как
    /// выключение сработало бы мгновенно.
    public func apply(_ config: RuleConfig) throws {
        try store.save(config)
        dispatch(.configChanged(store.config))
        reconcile()
    }

    /// Перечитывает конфиг с диска и сообщает движку прочитанное.
    ///
    /// Нужен, потому что `store.load()` зовётся ровно один раз за жизнь процесса, а карантин
    /// выставляется только внутри него: без перечитывания порча файла на живом приложении
    /// осталась бы незамеченной, а следующая запись затёрла бы правку, сделанную руками.
    /// Конфиг — человекочитаемый контракт, править его руками приглашают.
    ///
    /// Перечитывание — **не починка**: карантинный файл только сообщается, никогда не
    /// чинится, не мигрируется и не переписывается.
    public func reloadFromDisk() {
        store.load()
        dispatch(.configChanged(store.config))
        reconcile()
    }

    /// Пишет дневную свёртку фокуса на диск, если она изменилась с последнего слива.
    ///
    /// Синхронно и на главном потоке — не в `Task` и не на фоновой очереди. `ConfigStore`
    /// подметает из каталога данных любой файл с `.sb-` в имени, а `writeDurably` именует так
    /// свой временный файл; уборка, приехавшая посреди записи, снесла бы его. С TASK-006
    /// уборка зовётся при каждом открытии поповера, так что это не гипотеза.
    ///
    /// Не бросает: отказ слива — строка в логе, а не падение приложения. Лог здесь и есть
    /// весь диагностический канал (DEC-004).
    public func flushFocus() {
        let rollup = focusRollup
        guard rollup != lastFlushed else { return }

        do {
            let bytes = try focusStore.flush(rollup)
            lastFlushed = rollup
            focusLog.notice("focus written: path=\(self.focusStore.focusURL.path, privacy: .public) days=\(rollup.days.count, privacy: .public) bytes=\(bytes.count, privacy: .public)")
        } catch {
            let reason = String(describing: error)
            focusLog.notice("focus flush failed, file left untouched: path=\(self.focusStore.focusURL.path, privacy: .public) reason=\(reason, privacy: .public)")
        }
    }

    public func stop() {
        observer.stop()
        focusObserver.stop()
        tickTimer?.invalidate()
        tickTimer = nil
        sweepTimer?.invalidate()
        sweepTimer = nil
        flushTimer?.invalidate()
        flushTimer = nil
        for token in notificationTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        notificationTokens.removeAll()
    }

    // MARK: - Вход и эффекты

    /// Единственная точка, где во всём приложении читаются часы и строится `Now`.
    ///
    /// Читаются они парой и всегда вместе: стенные — для дедлайна, накопительные — для
    /// фокуса, пояс — для календарного дня. Ни одно из трёх полей не имеет значения по
    /// умолчанию, поэтому забыть одно нельзя: не соберётся.
    private var currentNow: Now {
        Now(wall: Date(), awake: currentAwakeInstant(), timeZone: .current)
    }

    private func dispatch(_ input: EngineInput) {
        perform(engine.handle(input, at: currentNow))
        // Единственная воронка, через которую проходит каждый вход, — поэтому и
        // единственная точка уведомления. Строго после `perform`: слушатель перечитывает
        // состояние движка, и оно обязано быть уже окончательным.
        onStateChanged?()
    }

    private func perform(_ effects: [Effect]) {
        for effect in effects {
            switch effect {
            case .log(let event):
                logRenderer.render(event)

            case .requestQuit(let session):
                sender.send(session) { [weak self] outcome in
                    self?.dispatch(.quitOutcome(pid: session.pid, outcome: outcome))
                }

            case .appFirstObserved:
                // Потребителя нет и в этой задаче не появляется. TASK-005 была
                // единственным потребителем и отложена 2026-08-28: quit не спрашивает
                // согласия вовсе, греть нечего (findings §5, амендмент 1 карточки).
                break
            }
        }
    }
}
