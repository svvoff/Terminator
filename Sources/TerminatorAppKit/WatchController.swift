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

    private var tickTimer: Timer?
    private var sweepTimer: Timer?
    private var notificationTokens: [any NSObjectProtocol] = []

    /// Каденция тика: дедлайн соблюдается в пределах одного тика, худший перелёт — 5 с.
    public static let tickInterval: TimeInterval = 5

    /// Каденция полной сверки.
    public static let sweepInterval: TimeInterval = 30

    public init(
        store: ConfigStore,
        expiryAction: any ExpiryAction = QuitImmediately(),
        observer: RunningApplicationsObserver = RunningApplicationsObserver(),
        sender: QuitSender = QuitSender(),
        logRenderer: EngineLogRenderer = EngineLogRenderer()
    ) {
        self.store = store
        self.engine = WatchEngine(expiryAction: expiryAction)
        self.observer = observer
        self.sender = sender
        self.logRenderer = logRenderer
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

    public func stop() {
        observer.stop()
        tickTimer?.invalidate()
        tickTimer = nil
        sweepTimer?.invalidate()
        sweepTimer = nil
        for token in notificationTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        notificationTokens.removeAll()
    }

    // MARK: - Вход и эффекты

    private func dispatch(_ input: EngineInput) {
        perform(engine.handle(input, at: Now(wall: Date())))
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
