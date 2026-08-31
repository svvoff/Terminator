import Foundation
import Testing

import TerminatorCore

/// Критерии приёмки TASK-004, пункты 1–22 и 25. Каждый тест синхронный: ни async, ни sleep, ни
/// реальных часов, ни `NSWorkspace`, ни файловой системы. Момент времени приходит
/// параметром, поэтому «прошло два часа» — это арифметика, а не ожидание (findings §13).
@Suite("Движок наблюдения")
struct WatchEngineTests {

    // MARK: - Истечение и лестница ретраев

    /// Критерий 1. Попытка засчитывается в момент эмиссии эффекта, а не по приходу исхода,
    /// иначе следующий тик через 5 с эмитил бы вторую отправку на ту же сессию.
    @Test func countdownExpiresExactlyOnce() throws {
        var engine = try engineWatching(slack, minutes: 10, enabledAt: t(-7200))
        // Сверка за пять секунд до дедлайна: она сама ничего не закрывает, первая отправка
        // приходится ровно на now(0).
        _ = engine.handle(.reconcile(observed: [running(slack, pid: 501, start: t(-600))]), at: now(-5))

        let first = engine.handle(.tick, at: now(5))
        let second = engine.handle(.tick, at: now(10))

        #expect(first.quitRequests.count == 1)
        #expect(second.quitRequests.isEmpty)
    }

    /// Критерий 2. Пять отправок за две минуты — на дедлайне и на +30, +60, +90, +120 —
    /// и терминальное состояние на +150. Шестой отправки не бывает никогда.
    @Test func retryCadenceAndCapWhenQuitIsRefused() throws {
        var engine = try engineWatching(slack, minutes: 10, enabledAt: t(-7200))
        // Сверка за пять секунд до дедлайна: она сама ничего не закрывает, первая отправка
        // приходится ровно на now(0).
        _ = engine.handle(.reconcile(observed: [running(slack, pid: 501, start: t(-600))]), at: now(-5))

        var sendMoments: [TimeInterval] = []
        for second in stride(from: 0.0, through: 300.0, by: 5.0) {
            let effects = engine.handle(.tick, at: now(second))
            for _ in effects.quitRequests { sendMoments.append(second) }
            // Каждая отправка честно отвечает «принято к доставке»: приложение живо и молчит.
            if !effects.quitRequests.isEmpty {
                _ = engine.handle(.quitOutcome(pid: 501, outcome: .requestSent), at: now(second))
            }
        }

        #expect(sendMoments == [0, 30, 60, 90, 120])
        #expect(sendMoments.count == WatchEngine.maximumAttempts)

        let session = try #require(engine.activeSessions.first)
        #expect(session.phase == .refused(.attemptsExhausted))

        // Ни одного quit после +150 с, сколько бы тиков ни пришло.
        for second in stride(from: 305.0, through: 900.0, by: 5.0) {
            #expect(engine.handle(.tick, at: now(second)).quitRequests.isEmpty)
        }
    }

    /// Критерий 3. Обработка `-1743` оборонительная: за семнадцать отправок против пяти
    /// приложений он не приходил ни разу (findings §5, DEC-002). Если придёт — терминален
    /// немедленно, без единого ретрая.
    @Test func permissionDeniedIsTerminalImmediately() throws {
        var engine = try engineWatching(slack, minutes: 10, enabledAt: t(-7200))
        // Сверка за пять секунд до дедлайна: она сама ничего не закрывает, первая отправка
        // приходится ровно на now(0).
        _ = engine.handle(.reconcile(observed: [running(slack, pid: 501, start: t(-600))]), at: now(-5))
        #expect(engine.handle(.tick, at: now(0)).quitRequests.count == 1)

        let refusal = engine.handle(
            .quitOutcome(pid: 501, outcome: .refused(QuitOutcome.eventNotPermitted)),
            at: now(1)
        )
        #expect(refusal.logKinds == [.quitRefused])
        #expect(refusal.logEvents.first?.refusal == .status(QuitOutcome.eventNotPermitted))

        let session = try #require(engine.activeSessions.first)
        #expect(session.phase == .refused(.status(QuitOutcome.eventNotPermitted)))

        for second in stride(from: 5.0, through: 600.0, by: 5.0) {
            #expect(engine.handle(.tick, at: now(second)).quitRequests.isEmpty)
        }
    }

    /// Критерий 4. Любой другой статус отказа — это состоявшаяся попытка, и лестница идёт
    /// до того же лимита в пять отправок.
    @Test func otherRefusalStatusRetriesUntilCap() throws {
        let procNotFound: OSStatus = -600
        var engine = try engineWatching(slack, minutes: 10, enabledAt: t(-7200))
        // Сверка за пять секунд до дедлайна: она сама ничего не закрывает, первая отправка
        // приходится ровно на now(0).
        _ = engine.handle(.reconcile(observed: [running(slack, pid: 501, start: t(-600))]), at: now(-5))

        var sends = 0
        for second in stride(from: 0.0, through: 300.0, by: 5.0) {
            let effects = engine.handle(.tick, at: now(second))
            sends += effects.quitRequests.count
            if !effects.quitRequests.isEmpty {
                _ = engine.handle(.quitOutcome(pid: 501, outcome: .refused(procNotFound)), at: now(second))
            }
        }

        #expect(sends == WatchEngine.maximumAttempts)
        #expect(engine.activeSessions.first?.phase == .refused(.attemptsExhausted))
    }

    // MARK: - Жизненный цикл процесса

    /// Критерий 5. Пользователь закрыл приложение сам, до дедлайна.
    @Test func userQuitBeforeExpiryCancelsCountdown() throws {
        var engine = try engineWatching(slack, minutes: 10, enabledAt: t(-60))
        _ = engine.handle(.reconcile(observed: [running(slack, pid: 501, start: t(-60))]), at: now(0))

        let terminated = engine.handle(.terminated(pid: 501), at: now(100))
        #expect(terminated.logKinds == [.appExited])
        #expect(engine.activeSessions.isEmpty)

        for second in stride(from: 105.0, through: 1200.0, by: 5.0) {
            #expect(engine.handle(.tick, at: now(second)).quitRequests.isEmpty)
        }
    }

    /// Критерий 6. Cooldown нет и памяти о прошлой сессии нет (DEC-003): новый процесс
    /// получает полный свежий лимит от собственного `p_starttime`.
    @Test func relaunchAfterQuitGetsFullFreshLimit() throws {
        var engine = try engineWatching(slack, minutes: 10, enabledAt: t(-7200))
        // Процесс просрочен ещё до того, как его увидели: quit эмитит сама сверка.
        let sweep = engine.handle(.reconcile(observed: [running(slack, pid: 501, start: t(-3600))]), at: now(0))
        #expect(sweep.quitRequests.count == 1)
        _ = engine.handle(.quitOutcome(pid: 501, outcome: .requestSent), at: now(0))
        _ = engine.handle(.terminated(pid: 501), at: now(1))

        let relaunchStart = t(30)
        _ = engine.handle(.observed(insertions: [running(slack, pid: 777, start: relaunchStart)]), at: now(31))

        let session = try #require(engine.activeSessions.first)
        #expect(session.pid == 777)
        #expect(session.deadline == relaunchStart.addingTimeInterval(600))
        #expect(session.phase == .counting)
    }

    /// Критерий 7. Приложение, уже запущенное на старте Terminator, принимается сверкой и
    /// считается от собственного времени старта, а не от момента сверки.
    @Test func appAlreadyRunningAtStartupIsAdopted() throws {
        var engine = try engineWatching(slack, minutes: 10, enabledAt: t(-7200))
        let start = t(-60)

        let adopted = engine.handle(.reconcile(observed: [running(slack, pid: 501, start: start)]), at: now(0))
        #expect(adopted.quitRequests.isEmpty)

        let session = try #require(engine.activeSessions.first)
        #expect(session.deadline == start.addingTimeInterval(600))
        #expect(session.deadline != now(0).wall.addingTimeInterval(600))

        // Дедлайн ровно через девять минут после сверки, ни секундой раньше.
        #expect(engine.handle(.tick, at: now(540 - 5)).quitRequests.isEmpty)
        #expect(engine.handle(.tick, at: now(540)).quitRequests.count == 1)
    }

    /// Критерий 8. Два приложения с разными лимитами считаются независимо.
    @Test func twoWatchedAppsCountDownIndependently() throws {
        var engine = WatchEngine(config: try RuleConfig([
            Rule(bundleIdentifier: slack, limit: .constant(.seconds(600)), enabledAt: t(-7200)),
            Rule(bundleIdentifier: telegram, limit: .constant(.seconds(1800)), enabledAt: t(-7200))
        ]))
        _ = engine.handle(.reconcile(observed: [
            running(slack, pid: 501, start: t(0)),
            running(telegram, pid: 502, start: t(0))
        ]), at: now(0))

        let atTenMinutes = engine.handle(.tick, at: now(600))
        #expect(atTenMinutes.quitRequests.map(\.bundleIdentifier) == [slack])
        _ = engine.handle(.terminated(pid: 501), at: now(601))

        #expect(engine.activeSessions.map(\.bundleIdentifier) == [telegram])
        #expect(engine.activeSessions.first?.phase == .counting)

        let atThirtyMinutes = engine.handle(.tick, at: now(1800))
        #expect(atThirtyMinutes.quitRequests.map(\.bundleIdentifier) == [telegram])
    }

    /// Критерий 9. Один bundle id, два pid с разным временем старта — два независимых
    /// отсчёта (findings §10: несколько живых процессов могут иметь один идентификатор).
    @Test func twoInstancesOfSameBundleIdCountDownIndependently() throws {
        var engine = try engineWatching(slack, minutes: 10, enabledAt: t(-7200))
        _ = engine.handle(.reconcile(observed: [
            running(slack, pid: 501, start: t(0)),
            running(slack, pid: 502, start: t(120))
        ]), at: now(0))

        #expect(engine.activeSessions.count == 2)
        #expect(engine.activeSessions.map(\.deadline) == [t(600), t(720)])

        let firstDeadline = engine.handle(.tick, at: now(600))
        #expect(firstDeadline.quitRequests.map(\.pid) == [501])

        _ = engine.handle(.terminated(pid: 501), at: now(601))
        let survivor = try #require(engine.activeSessions.first)
        #expect(engine.activeSessions.count == 1)
        #expect(survivor.pid == 502)
        #expect(survivor.phase == .counting)
        #expect(survivor.deadline == t(720))

        #expect(engine.handle(.tick, at: now(720)).quitRequests.map(\.pid) == [502])
    }

    // MARK: - Правки конфига

    /// Критерий 10. Смена лимита не переякоривает: дедлайн пересчитывается от прежнего
    /// якоря, а укороченный ниже прошедшего времени лимит истекает на ближайшем тике
    /// (DEC-001).
    @Test func changingLimitMidCountdownDoesNotReAnchor() throws {
        let enabledAt = t(-7200)
        let start = t(-600)
        var engine = try engineWatching(slack, minutes: 30, enabledAt: enabledAt)
        _ = engine.handle(.reconcile(observed: [running(slack, pid: 501, start: start)]), at: now(0))
        #expect(engine.activeSessions.first?.deadline == start.addingTimeInterval(1800))

        let shortened = try RuleConfig([
            Rule(bundleIdentifier: slack, limit: .constant(.seconds(300)), enabledAt: enabledAt)
        ])
        let edit = engine.handle(.configChanged(shortened), at: now(0))

        // Якорь тот же — время старта процесса, а не момент правки.
        #expect(engine.activeSessions.first?.deadline == start.addingTimeInterval(300))
        // Сама правка не закрывает: это делает ближайший тик.
        #expect(edit.quitRequests.isEmpty)
        #expect(engine.handle(.tick, at: now(5)).quitRequests.count == 1)
    }

    /// Критерий 11. Включение правила ставит `enabledAt = now` и потому переякоривает, и
    /// закончиться немедленным quit оно не может никогда, сколько бы процесс ни работал
    /// (DEC-001). Проверены оба пути: сессия, которая уже идёт, и правило, включённое из
    /// выключенного состояния.
    @Test func enablingRuleMidRunReAnchors() throws {
        let start = t(-3600)

        // Путь 1: отсчёт уже идёт, правило перевключили.
        var engine = try engineWatching(slack, minutes: 30, enabledAt: t(-120))
        _ = engine.handle(.reconcile(observed: [running(slack, pid: 501, start: start)]), at: now(0))

        let reEnabled = try RuleConfig([
            Rule(bundleIdentifier: slack, limit: .constant(.seconds(1800)), enabledAt: now(0).wall)
        ])
        let enabling = engine.handle(.configChanged(reEnabled), at: now(0))
        #expect(enabling.quitRequests.isEmpty)
        #expect(engine.activeSessions.first?.deadline == now(0).wall.addingTimeInterval(1800))
        #expect(engine.activeSessions.first?.deadline != start.addingTimeInterval(1800))
        #expect(engine.handle(.tick, at: now(5)).quitRequests.isEmpty)

        // Путь 2: правило было выключено, отсчёта не было вовсе.
        var fresh = WatchEngine(config: try RuleConfig([
            Rule(bundleIdentifier: slack, limit: .constant(.seconds(1800)), enabledAt: nil)
        ]))
        _ = fresh.handle(.reconcile(observed: [running(slack, pid: 501, start: start)]), at: now(0))
        #expect(fresh.activeSessions.isEmpty)

        let turnedOn = try RuleConfig([
            Rule(bundleIdentifier: slack, limit: .constant(.seconds(1800)), enabledAt: now(0).wall)
        ])
        #expect(fresh.handle(.configChanged(turnedOn), at: now(0)).quitRequests.isEmpty)
        let adopted = fresh.handle(.reconcile(observed: [running(slack, pid: 501, start: start)]), at: now(0))
        #expect(adopted.quitRequests.isEmpty)
        #expect(fresh.activeSessions.first?.deadline == now(0).wall.addingTimeInterval(1800))
        #expect(fresh.handle(.tick, at: now(5)).quitRequests.isEmpty)
    }

    /// Критерий 17. Выключение правила снимает все сессии этого bundle id, включая ту, что
    /// уже в середине лестницы ретраев.
    @Test func disablingRuleStopsCountdownAndRetries() throws {
        let enabledAt = t(-7200)
        var engine = try engineWatching(slack, minutes: 10, enabledAt: enabledAt)
        _ = engine.handle(.reconcile(observed: [
            running(slack, pid: 501, start: t(-600)),
            running(slack, pid: 502, start: t(-600))
        ]), at: now(-5))
        #expect(engine.handle(.tick, at: now(0)).quitRequests.count == 2)
        for session in engine.activeSessions {
            guard case .awaitingQuit = session.phase else {
                Issue.record("сессия должна быть в .awaitingQuit до выключения правила")
                return
            }
        }

        let disabled = try RuleConfig([
            Rule(bundleIdentifier: slack, limit: .constant(.seconds(600)), enabledAt: nil)
        ])
        #expect(engine.handle(.configChanged(disabled), at: now(1)).quitRequests.isEmpty)
        #expect(engine.activeSessions.isEmpty)

        for second in stride(from: 5.0, through: 600.0, by: 5.0) {
            #expect(engine.handle(.tick, at: now(second)).quitRequests.isEmpty)
        }
    }

    // MARK: - Просроченное на первом же проходе

    /// Критерий 12. Grace-периода нет: процесс, просроченный ещё до того, как его увидели,
    /// закрывается на том же проходе (DEC-001).
    @Test func overBudgetAppFoundAtStartupIsQuitAtFirstSweep() throws {
        var engine = try engineWatching(slack, minutes: 10, enabledAt: t(-10800))
        let effects = engine.handle(
            .reconcile(observed: [running(slack, pid: 501, start: t(-7200))]),
            at: now(0)
        )

        #expect(effects.quitRequests.map(\.pid) == [501])
        #expect(effects.logKinds == [.appDetected, .countdownStarted, .quitRequested])
    }

    /// Критерий 21. Просроченный `enabledAt`, прочитанный с диска, даёт немедленный quit на
    /// первой же сверке. Включение правила такого состояния не даёт никогда — только
    /// конфиг, лежавший на диске, пока Terminator не работал (DEC-001).
    @Test func staleEnabledAtFromConfigIsOverdueAtStartup() throws {
        let enabledAt = t(-7200)
        var engine = WatchEngine()
        _ = engine.handle(.configChanged(try RuleConfig([
            Rule(bundleIdentifier: slack, limit: .constant(.seconds(600)), enabledAt: enabledAt)
        ])), at: now(0))

        let sweep = engine.handle(
            .reconcile(observed: [running(slack, pid: 501, start: t(-10800))]),
            at: now(0)
        )

        // Якорь — enabledAt, он позже времени старта процесса.
        let session = try #require(engine.activeSessions.first)
        #expect(session.deadline == enabledAt.addingTimeInterval(600))
        #expect(session.deadline.timeIntervalSince(now(0).wall) == -6600)
        #expect(sweep.quitRequests.map(\.pid) == [501])
    }

    /// Критерий 20. Дедлайн истёк между двумя сверками, тика между ними не было — Mac спал.
    /// Quit эмитит сама вторая сверка: она оценивает дедлайны, а не только принимает.
    @Test func wakeSweepQuitsOverdueSession() throws {
        var engine = try engineWatching(slack, minutes: 10, enabledAt: t(-60))
        let snapshot = [running(slack, pid: 501, start: t(0))]

        let beforeSleep = engine.handle(.reconcile(observed: snapshot), at: now(0))
        #expect(beforeSleep.quitRequests.isEmpty)

        // Восемь часов сна: тиков не было, стенные часы ушли вперёд.
        let afterWake = engine.handle(.reconcile(observed: snapshot), at: now(28_800))
        #expect(afterWake.quitRequests.map(\.pid) == [501])
    }

    // MARK: - Снятие сессий

    /// Критерий 13. `.notRunning` снимает сессию без ошибки и без ретрая.
    @Test func staleSessionIsDroppedNotRetried() throws {
        var engine = try engineWatching(slack, minutes: 10, enabledAt: t(-7200))
        // Сверка за пять секунд до дедлайна: она сама ничего не закрывает, первая отправка
        // приходится ровно на now(0).
        _ = engine.handle(.reconcile(observed: [running(slack, pid: 501, start: t(-600))]), at: now(-5))
        #expect(engine.handle(.tick, at: now(0)).quitRequests.count == 1)

        let outcome = engine.handle(.quitOutcome(pid: 501, outcome: .notRunning), at: now(1))
        #expect(outcome.logKinds == [.appExited])
        #expect(engine.activeSessions.isEmpty)

        for second in stride(from: 5.0, through: 600.0, by: 5.0) {
            #expect(engine.handle(.tick, at: now(second)).quitRequests.isEmpty)
        }
    }

    /// Критерий 19. Сверка, которая только принимает и не удаляет, проходит большинство
    /// тестов и при этом навсегда копит мёртвые сессии — и шлёт quit переиспользованному
    /// pid. Здесь KVO-удаление не приходило вовсе.
    @Test func sessionAbsentFromReconcileIsDropped() throws {
        var engine = try engineWatching(slack, minutes: 10, enabledAt: t(-7200))
        // Сверка за пять секунд до дедлайна: она сама ничего не закрывает, первая отправка
        // приходится ровно на now(0).
        _ = engine.handle(.reconcile(observed: [running(slack, pid: 501, start: t(-600))]), at: now(-5))
        #expect(engine.handle(.tick, at: now(0)).quitRequests.count == 1)
        guard case .awaitingQuit = try #require(engine.activeSessions.first).phase else {
            Issue.record("сессия должна быть в .awaitingQuit")
            return
        }

        let sweep = engine.handle(.reconcile(observed: []), at: now(10))
        #expect(sweep.logKinds == [.appExited])
        #expect(engine.activeSessions.isEmpty)

        for second in stride(from: 15.0, through: 600.0, by: 5.0) {
            #expect(engine.handle(.tick, at: now(second)).quitRequests.isEmpty)
        }
    }

    /// Критерий 25. Процесс уже мёртв, но ещё висит в снимке: ядро молчит, времени старта
    /// нет, а список ещё не догнал (findings §4 — отставание до 19 с). Сессия снимается ровно
    /// одним `app-exited`, новая не заводится, quit не эмитится — ни на этой сверке, ни на
    /// любом следующем тике.
    ///
    /// Это юнит-тестовая форма трассы с машины автора. Там адаптер в этом окне откатывался на
    /// `launchDate`, и расхождение в 8 мс делало из трупа второй процесс на том же pid:
    /// настоящая сессия снималась ложным `app-exited`, на её месте заводилась фантомная и
    /// сразу просроченная, и одно закрытие давало два `quit-requested`. Откат удалён
    /// (амендмент 3 карточки); тест фиксирует контракт со стороны движка — время старта nil
    /// значит «не принимать», а не «взять другое».
    @Test func deadProcessStillListedDoesNotResurrectSession() throws {
        var engine = try engineWatching(slack, minutes: 10, enabledAt: t(-7200))
        _ = engine.handle(.reconcile(observed: [running(slack, pid: 501, start: t(-600))]), at: now(-5))
        #expect(engine.handle(.tick, at: now(0)).quitRequests.count == 1)

        // Тот же pid всё ещё в снимке, но времени старта у него больше нет.
        let listedButDead = ObservedProcess(
            pid: 501,
            bundleIdentifier: slack,
            startTime: nil,
            activationPolicy: .regular
        )
        let sweep = engine.handle(.reconcile(observed: [listedButDead]), at: now(1))

        #expect(sweep.logKinds == [.appExited])
        #expect(sweep.quitRequests.isEmpty)
        #expect(engine.activeSessions.isEmpty)

        // Пока окно не закрылось, сверки повторяются с тем же снимком — и молчат.
        for second in stride(from: 5.0, through: 600.0, by: 5.0) {
            #expect(engine.handle(.reconcile(observed: [listedButDead]), at: now(second)).isEmpty)
            #expect(engine.handle(.tick, at: now(second)).quitRequests.isEmpty)
        }
        #expect(engine.activeSessions.isEmpty)
    }

    // MARK: - Отказы принятия, которые не запоминаются

    /// Критерий 14. Процесс без bundle id игнорируется на этот проход и переоценивается на
    /// следующей сверке — в множество «отвергнутых навсегда» он не попадает.
    @Test func processWithNilBundleIdentifierIsNotDiscardedPermanently() throws {
        let start = t(-60)
        var engine = try engineWatching(slack, minutes: 10, enabledAt: t(-7200))

        let anonymous = ObservedProcess(
            pid: 501,
            bundleIdentifier: nil,
            startTime: start,
            activationPolicy: .regular
        )
        let ignored = engine.handle(.reconcile(observed: [anonymous]), at: now(0))
        #expect(ignored.isEmpty)
        #expect(engine.activeSessions.isEmpty)

        let named = engine.handle(.reconcile(observed: [running(slack, pid: 501, start: start)]), at: now(30))
        #expect(named.quitRequests.isEmpty)
        let session = try #require(engine.activeSessions.first)
        #expect(session.deadline == start.addingTimeInterval(600))
    }

    /// Критерий 15. Без времени старта отсчёта нет — и никакого отката на `Date()`
    /// (findings §3). Процесс переоценивается на следующей сверке.
    @Test func processWithoutLaunchTimeDoesNotStartCountdown() throws {
        var engine = try engineWatching(slack, minutes: 10, enabledAt: t(-7200))

        let timeless = ObservedProcess(
            pid: 501,
            bundleIdentifier: slack,
            startTime: nil,
            activationPolicy: .regular
        )
        let seen = engine.handle(.reconcile(observed: [timeless]), at: now(0))
        #expect(seen.quitRequests.isEmpty)
        #expect(engine.activeSessions.isEmpty)
        // Приложение увидено, но не считается: `app-detected` без `countdown-started`.
        #expect(seen.logKinds == [.appDetected])
        #expect(engine.handle(.tick, at: now(3600)).quitRequests.isEmpty)

        let start = t(-60)
        _ = engine.handle(.reconcile(observed: [running(slack, pid: 501, start: start)]), at: now(30))
        #expect(engine.activeSessions.first?.deadline == start.addingTimeInterval(600))
    }

    /// Критерий 16. Гард `.regular` — часть сопоставления правила (findings §10), и живёт
    /// он в редьюсере, поэтому проверяется здесь, а не глазами по адаптеру.
    @Test func nonRegularActivationPolicyIsIgnored() throws {
        var engine = try engineWatching(slack, minutes: 10, enabledAt: t(-7200))

        let accessory = ObservedProcess(
            pid: 501,
            bundleIdentifier: slack,
            startTime: t(-7200),
            activationPolicy: .accessory
        )
        let effects = engine.handle(.reconcile(observed: [accessory]), at: now(0))

        #expect(effects.isEmpty)
        #expect(engine.activeSessions.isEmpty)
        for second in stride(from: 5.0, through: 600.0, by: 5.0) {
            #expect(engine.handle(.tick, at: now(second)).quitRequests.isEmpty)
        }
    }

    // MARK: - Лог и шов

    /// Критерий 18. Полный прогон даёт все шесть событий: обнаружено, отсчёт начат, quit
    /// отправлен, повторён, отказ терминален, приложение исчезло.
    @Test func lifecycleEmitsAllSixLogEvents() throws {
        var engine = try engineWatching(slack, minutes: 10, enabledAt: t(-3600))
        var kinds: [LogEvent.Kind] = []

        kinds += engine.handle(
            .reconcile(observed: [running(slack, pid: 501, start: t(-3600))]),
            at: now(0)
        ).logKinds

        for second in stride(from: 0.0, through: 150.0, by: 5.0) {
            let effects = engine.handle(.tick, at: now(second))
            kinds += effects.logKinds
            if !effects.quitRequests.isEmpty {
                _ = engine.handle(.quitOutcome(pid: 501, outcome: .requestSent), at: now(second))
            }
        }
        kinds += engine.handle(.terminated(pid: 501), at: now(200)).logKinds

        #expect(kinds == [
            .appDetected,
            .countdownStarted,
            .quitRequested,
            .quitRetry, .quitRetry, .quitRetry, .quitRetry,
            .quitRefused,
            .appExited
        ])
    }

    /// Критерий 22. Эффект — про bundle id, а не про сессию: второй экземпляр того же
    /// приложения его не повторяет, другой наблюдаемый идентификатор даёт свой.
    ///
    /// Потребителя у эффекта нет: TASK-005 отложена, и подключать его в этой задаче не к
    /// чему (амендмент 1 карточки).
    @Test func firstObservationOfBundleEmitsAppFirstObserved() throws {
        var engine = WatchEngine(config: try RuleConfig([
            Rule(bundleIdentifier: slack, limit: .constant(.seconds(600)), enabledAt: t(-7200)),
            Rule(bundleIdentifier: telegram, limit: .constant(.seconds(600)), enabledAt: t(-7200))
        ]))

        let first = engine.handle(.reconcile(observed: [running(slack, pid: 501, start: t(0))]), at: now(0))
        #expect(first.firstObservations == [slack])

        // Второй экземпляр того же приложения — отсчёт свой, эффекта нет.
        let secondInstance = engine.handle(
            .observed(insertions: [running(slack, pid: 502, start: t(1))]),
            at: now(1)
        )
        #expect(secondInstance.firstObservations.isEmpty)
        #expect(engine.activeSessions.count == 2)

        // Любой следующий вход — тоже нет.
        #expect(engine.handle(.reconcile(observed: [
            running(slack, pid: 501, start: t(0)),
            running(slack, pid: 502, start: t(1))
        ]), at: now(2)).firstObservations.isEmpty)

        // Другой наблюдаемый идентификатор даёт свой.
        let other = engine.handle(
            .observed(insertions: [running(telegram, pid: 601, start: t(3))]),
            at: now(3)
        )
        #expect(other.firstObservations == [telegram])
    }
}

// MARK: - Фикстуры

/// Подопытные идентификаторы. Реальные строки взяты только затем, чтобы тест читался как
/// сценарий; ничего из этого в тестах не запускается и не адресуется.
private let slack = "com.tinyspeck.slackmacgap"
private let telegram = "ru.keepcoder.Telegram"

/// Фиксированная точка отсчёта: тесты не читают реальные часы вообще.
private let epoch = Date(timeIntervalSince1970: 1_756_300_000)

/// Момент на шкале стенных часов: `t(-3600)` — час назад относительно точки отсчёта.
private func t(_ offset: TimeInterval) -> Date {
    epoch.addingTimeInterval(offset)
}

/// Момент для редьюсера. Все три поля обязательны — у `Now` нет умолчаний.
///
/// Накопительное чтение идёт вровень со стенным: в этих тестах машина не спит, а сценарии
/// TASK-004 его не читают вовсе. Пояс — UTC, чтобы день не зависел от машины, на которой
/// гоняют тесты.
private func now(_ offset: TimeInterval) -> Now {
    Now(
        wall: t(offset),
        awake: AwakeInstant(sinceOrigin: .seconds(1_000_000 + offset)),
        timeZone: TimeZone(secondsFromGMT: 0)!
    )
}

private func engineWatching(
    _ bundleIdentifier: String,
    minutes: Int,
    enabledAt: Date?
) throws -> WatchEngine {
    WatchEngine(config: RuleConfig([
        try Rule(
            bundleIdentifier: bundleIdentifier,
            limit: .constant(.seconds(minutes * 60)),
            enabledAt: enabledAt
        )
    ]))
}

private func running(
    _ bundleIdentifier: String,
    pid: pid_t,
    start: Date
) -> ObservedProcess {
    ObservedProcess(
        pid: pid,
        bundleIdentifier: bundleIdentifier,
        startTime: start,
        activationPolicy: .regular
    )
}

extension [Effect] {

    fileprivate var quitRequests: [ProcessSession] {
        compactMap { effect in
            if case .requestQuit(let session) = effect { session } else { nil }
        }
    }

    fileprivate var logEvents: [LogEvent] {
        compactMap { effect in
            if case .log(let event) = effect { event } else { nil }
        }
    }

    fileprivate var logKinds: [LogEvent.Kind] {
        logEvents.map(\.kind)
    }

    fileprivate var firstObservations: [String] {
        compactMap { effect in
            if case .appFirstObserved(let bundleIdentifier, _) = effect { bundleIdentifier } else { nil }
        }
    }
}
