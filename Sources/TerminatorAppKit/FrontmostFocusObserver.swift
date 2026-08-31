import AppKit
import Foundation
import os

import TerminatorCore

/// Логгер учёта фокуса: собственные строки наблюдателя и слива, категория `focus`.
///
/// Отдельный логгер, а не эффект движка: `Effect.log(LogEvent)` рендерится единственным
/// типом, который пишет в категорию `engine`, а `LogEvent` несёт `bundleIdentifier` и `pid`
/// **необязательными не являющимися** полями — у паузы, смены дня и слива нет ни того, ни
/// другого. Редьюсер лог-событий фокуса не эмитит вовсе (амендмент 1 карточки).
///
/// Каждая интерполяция несёт `privacy: .public` — без исключений. Редакция происходит в
/// момент записи и необратима (findings §14), а лог — единственный диагностический канал
/// продукта (DEC-004).
nonisolated let focusLog = Logger(subsystem: TerminatorLog.subsystem, category: TerminatorLog.Category.focus)

/// Чтение накопительных часов — **suspending**-семья, та, что стоит во сне машины.
///
/// `ProcessInfo.systemUptime` измерен как член этой семьи вместе с `mach_absolute_time`,
/// `CLOCK_UPTIME_RAW` и `DispatchTime.now()`: на машине автора она отстала от сон-инклюзивной
/// семьи на 152 626 с при 178.8 ч бодрствования (findings §9). Именно это здесь и нужно:
/// восемь часов сна Mac обязаны дать ноль секунд фокуса.
///
/// Голое число живёт ровно одно выражение и сразу заворачивается в `AwakeInstant`: дальше по
/// коду накопительное чтение не бывает ни `TimeInterval`, ни `Date`.
nonisolated func currentAwakeInstant() -> AwakeInstant {
    AwakeInstant(sinceOrigin: .seconds(ProcessInfo.processInfo.systemUptime))
}

/// Наблюдатель фокуса: кто фронтмост, когда накопление приостановлено и когда сменился день.
///
/// Наблюдение за фронтмостом — **KVO**, по той же причине, что и за списком процессов:
/// уведомления не являются источником истины (findings §2). Подписка **системная** и не
/// сужена до наблюдаемых bundle id — сужённая не увидела бы приложения, против которого надо
/// закрыть текущий спан (DEC-005). Фильтрует движок.
///
/// Решений здесь нет ни одного: наблюдатель переводит мир в четыре входа и пишет строку в
/// лог. Что считать, когда пауза и куда отнести секунды, решает редьюсер.
public final class FrontmostFocusObserver {

    private var observation: NSKeyValueObservation?
    private var workspaceTokens: [any NSObjectProtocol] = []
    private var distributedTokens: [any NSObjectProtocol] = []
    private var timeZoneToken: (any NSObjectProtocol)?
    private var midnightTimer: Timer?
    private var emit: (@MainActor @Sendable (EngineInput) -> Void)?

    /// Пары «уведомление рабочего пространства → причина паузы». Три из четырёх причин
    /// приходят отсюда.
    private static let workspaceSignals: [(name: NSNotification.Name, reason: FocusPauseReason, isPause: Bool)] = [
        (NSWorkspace.willSleepNotification, .systemSleep, true),
        (NSWorkspace.didWakeNotification, .systemSleep, false),
        (NSWorkspace.screensDidSleepNotification, .displaySleep, true),
        (NSWorkspace.screensDidWakeNotification, .displaySleep, false),
        (NSWorkspace.sessionDidResignActiveNotification, .sessionResignedActive, true),
        (NSWorkspace.sessionDidBecomeActiveNotification, .sessionResignedActive, false)
    ]

    /// Блокировка экрана приходит распределённым уведомлением: у `NSWorkspace` парного
    /// сигнала нет. Имена задокументированы Apple не были и findings их не мерили — это
    /// проверяется пунктом ручного чеклиста, а не утверждается здесь.
    private static let lockSignals: [(name: String, reason: FocusPauseReason, isPause: Bool)] = [
        ("com.apple.screenIsLocked", .screenLocked, true),
        ("com.apple.screenIsUnlocked", .screenLocked, false)
    ]

    public init() {}

    /// Начинает наблюдение. Все четыре входа фокуса уходят в `onInput`.
    public func start(onInput: @escaping @MainActor @Sendable (EngineInput) -> Void) {
        emit = onInput

        // Поток доставки KVO не оговорен: уведомление приходит на том потоке, который сменил
        // фронтмост. Поэтому здесь снимается Sendable-значение, а движок трогается уже на
        // главной очереди — `MainActor.assumeIsolated` на чужом потоке не «предположил бы»,
        // а уронил бы процесс.
        observation = NSWorkspace.shared.observe(
            \.frontmostApplication,
            options: [.new]
        ) { _, change in
            // Двойная опциональность: «ключ отсутствует» и «значение равно nil» — разные
            // вещи, и обе означают одно: фронтмост нет.
            let app = (change.newValue ?? nil).map(frontmostApp(from:))
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    focusLog.notice("frontmost changed: bundleID=\(app?.bundleIdentifier ?? "-", privacy: .public) pid=\(app?.pid ?? -1, privacy: .public) policy=\(describe(app?.activationPolicy), privacy: .public)")
                    onInput(.frontmostChanged(app))
                }
            }
        }

        for signal in Self.workspaceSignals {
            let token = NSWorkspace.shared.notificationCenter.addObserver(
                forName: signal.name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.deliver(signal.reason, isPause: signal.isPause) }
            }
            workspaceTokens.append(token)
        }

        for signal in Self.lockSignals {
            let token = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(signal.name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.deliver(signal.reason, isPause: signal.isPause) }
            }
            distributedTokens.append(token)
        }

        timeZoneToken = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                focusLog.notice("time zone changed: zone=\(TimeZone.current.identifier, privacy: .public)")
                self?.emit?(.dayRollover)
                self?.armMidnightTimer()
            }
        }

        armMidnightTimer()

        // Стартовый снимок: KVO сообщает смены, а не текущее значение, и без этой строки
        // спан не открылся бы до первого переключения приложений.
        let current = NSWorkspace.shared.frontmostApplication.map(frontmostApp(from:))
        focusLog.notice("focus observation started: frontmostBundleID=\(current?.bundleIdentifier ?? "-", privacy: .public) zone=\(TimeZone.current.identifier, privacy: .public)")
        onInput(.frontmostChanged(current))
    }

    public func stop() {
        observation?.invalidate()
        observation = nil
        for token in workspaceTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceTokens.removeAll()
        for token in distributedTokens {
            DistributedNotificationCenter.default().removeObserver(token)
        }
        distributedTokens.removeAll()
        if let timeZoneToken {
            NotificationCenter.default.removeObserver(timeZoneToken)
        }
        timeZoneToken = nil
        midnightTimer?.invalidate()
        midnightTimer = nil
        emit = nil
    }

    // Таймер полуночи здесь не гасится: `Timer` не `Sendable`, а трогать его из
    // nonisolated deinit Swift 6 не даёт. Утечки нет — замыкание держит `self` слабо, так
    // что после смерти наблюдателя срабатывание ничего не делает; штатный путь остановки —
    // `stop()`.
    deinit {
        observation?.invalidate()
    }

    // MARK: - Пауза и возобновление

    private func deliver(_ reason: FocusPauseReason, isPause: Bool) {
        focusLog.notice("focus \(isPause ? "paused" : "resumed", privacy: .public): reason=\(reason.rawValue, privacy: .public)")
        emit?(isPause ? .focusPaused(reason) : .focusResumed(reason))
    }

    // MARK: - Смена дня

    /// Взводит таймер на ближайшую **местную** полночь и перевзводит себя после срабатывания.
    ///
    /// Пунктуальность таймера основанием ни для чего не является: `Timer` живёт на
    /// suspending-семье и во сне стоит (findings §9), так что опоздание после ночного сна —
    /// норма. Ключ дня движок выводит из `now.wall`, поэтому опоздавший или потерянный
    /// сигнал исправляется ближайшим следующим начислением, а не теряет секунды.
    private func armMidnightTimer() {
        midnightTimer?.invalidate()

        let now = Date()
        let midnight = DayKey.startOfNextDay(after: now, in: TimeZone.current)
        let interval = max(1, midnight.timeIntervalSince(now))

        midnightTimer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                focusLog.notice("day rollover: at=\(logStamp(Date()), privacy: .public)")
                self?.emit?(.dayRollover)
                self?.armMidnightTimer()
            }
        }
    }
}

/// Перевод живого `NSRunningApplication` в то, что понимает ядро.
///
/// `processIdentifier` читается здесь, в точке использования, и никуда не кэшируется
/// (findings §10). Время старта берётся из `p_starttime` тем же путём, что и для отсчёта, —
/// иначе ключ открытого спана не сошёлся бы с ключом сессии в таблице движка, и слив по
/// удалению сессии не срабатывал бы.
nonisolated func frontmostApp(from application: NSRunningApplication) -> FrontmostApp {
    FrontmostApp(
        pid: application.processIdentifier,
        bundleIdentifier: application.bundleIdentifier,
        startTime: launchAnchor(of: application),
        activationPolicy: corePolicy(application.activationPolicy)
    )
}

/// Политика активации строкой для лога.
nonisolated func describe(_ policy: ProcessActivationPolicy?) -> String {
    switch policy {
    case nil: "-"
    case .regular: "regular"
    case .accessory: "accessory"
    case .prohibited: "prohibited"
    }
}
