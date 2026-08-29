import Foundation
import Testing

import TerminatorCore

/// Критерии приёмки TASK-006, пункты 1–3, 6 и 12. Каждый тест синхронный: ни AppKit, ни
/// запущенного меню-бара, ни sleep. Момент времени приходит параметром, поэтому «прошло
/// девять минут» — это другой `Date`, а не ожидание.
@Suite("Вью-модель поповера")
struct PopoverViewModelTests {

    // MARK: - Формат остатка

    /// Меньше часа — `m:ss`.
    @Test func remainingTimeUnderOneHourFormatsAsMinutesAndSeconds() {
        #expect(PopoverViewModel.remainingText(deadline: t(572), now: t(0)) == "9:32")
        #expect(PopoverViewModel.remainingText(deadline: t(3599), now: t(0)) == "59:59")
        #expect(PopoverViewModel.remainingText(deadline: t(1), now: t(0)) == "0:01")
    }

    /// Час и больше — `h:mm:ss`.
    @Test func remainingTimeAtOrAboveOneHourFormatsAsHoursMinutesSeconds() {
        #expect(PopoverViewModel.remainingText(deadline: t(3847), now: t(0)) == "1:04:07")
        #expect(PopoverViewModel.remainingText(deadline: t(3600), now: t(0)) == "1:00:00")
        #expect(PopoverViewModel.remainingText(deadline: t(28800), now: t(0)) == "8:00:00")
    }

    /// Прошедший дедлайн — `0:00`. Никогда отрицательное и никогда исчезновение строки.
    @Test func deadlineAlreadyPastFormatsAsZero() throws {
        #expect(PopoverViewModel.remainingText(deadline: t(0), now: t(0)) == "0:00")
        #expect(PopoverViewModel.remainingText(deadline: t(-1), now: t(0)) == "0:00")
        #expect(PopoverViewModel.remainingText(deadline: t(-9999), now: t(0)) == "0:00")

        // И строка не исчезает: правило по-прежнему даёт ровно один экземпляр.
        let model = PopoverViewModel(
            config: try config([rule(slack, minutes: 10)]),
            sessions: [session(slack, pid: 501, start: t(-3600), deadline: t(-30))],
            quarantine: nil,
            now: t(0)
        )
        let instance = try #require(model.rows.first?.instances.first)
        #expect(instance.remaining == 0)
        #expect(instance.remainingText == "0:00")
    }

    /// Вью-модель берёт `now` параметром: тест сдвигает время передачей другого `Date`,
    /// а не ожиданием.
    @Test func remainingTimeIsComputedFromSuppliedNow() throws {
        let rules = try config([rule(slack, minutes: 10)])
        let sessions = [session(slack, pid: 501, start: t(-100), deadline: t(600))]

        let atStart = PopoverViewModel(config: rules, sessions: sessions, quarantine: nil, now: t(0))
        let later = PopoverViewModel(config: rules, sessions: sessions, quarantine: nil, now: t(28))

        let first = try #require(atStart.rows.first?.instances.first)
        let second = try #require(later.rows.first?.instances.first)
        #expect(first.remainingText == "10:00")
        #expect(second.remainingText == "9:32")
    }

    // MARK: - Порядок строк

    /// Строки идут по возрастанию остатка.
    @Test func rowsSortAscendingByRemainingTime() throws {
        let model = PopoverViewModel(
            config: try config([
                rule(slack, minutes: 60),
                rule(telegram, minutes: 60),
                rule(safari, minutes: 60)
            ]),
            sessions: [
                session(slack, pid: 501, start: t(-100), deadline: t(900)),
                session(telegram, pid: 502, start: t(-100), deadline: t(120)),
                session(safari, pid: 503, start: t(-100), deadline: t(400))
            ],
            quarantine: nil,
            now: t(0)
        )

        #expect(model.rows.map(\.bundleIdentifier) == [telegram, safari, slack])
    }

    /// Правила без запущенных экземпляров идут после правил с ними, каким бы близким ни был
    /// чужой дедлайн.
    @Test func rulesWithNoRunningInstanceSortAfterRunningOnes() throws {
        let model = PopoverViewModel(
            config: try config([
                rule(safari, minutes: 60),
                rule(slack, minutes: 60)
            ]),
            // Запущен только Slack, и остаток у него большой.
            sessions: [session(slack, pid: 501, start: t(-100), deadline: t(9999))],
            quarantine: nil,
            now: t(0)
        )

        #expect(model.rows.map(\.bundleIdentifier) == [slack, safari])
        #expect(model.rows[0].instances.count == 1)
        #expect(model.rows[1].instances.isEmpty)
    }

    /// Выключенные — последними, даже если по алфавиту они первые.
    @Test func disabledRulesSortLast() throws {
        let model = PopoverViewModel(
            config: try config([
                rule(safari, minutes: 60, enabled: false),
                rule(slack, minutes: 60),
                rule(telegram, minutes: 60)
            ]),
            sessions: [session(telegram, pid: 502, start: t(-100), deadline: t(300))],
            quarantine: nil,
            now: t(0)
        )

        // telegram запущен, slack включён но не запущен, safari выключен.
        #expect(model.rows.map(\.bundleIdentifier) == [telegram, slack, safari])
        #expect(model.rows.last?.isEnabled == false)
    }

    /// Ничьи разрешаются по `bundleIdentifier` по возрастанию — порядок детерминирован.
    @Test func equalRemainingTimesBreakTieByBundleIdentifier() throws {
        let model = PopoverViewModel(
            config: try config([
                rule(telegram, minutes: 60),
                rule(slack, minutes: 60),
                rule(safari, minutes: 60)
            ]),
            sessions: [
                session(telegram, pid: 502, start: t(-100), deadline: t(600)),
                session(slack, pid: 501, start: t(-100), deadline: t(600)),
                session(safari, pid: 503, start: t(-100), deadline: t(600))
            ],
            quarantine: nil,
            now: t(0)
        )

        #expect(model.rows.map(\.bundleIdentifier) == [slack, safari, telegram].sorted())
        #expect(model.rows.map(\.bundleIdentifier) == model.rows.map(\.bundleIdentifier).sorted())
    }

    // MARK: - Пустое состояние и несколько экземпляров

    /// Ноль правил — пустое состояние.
    @Test func emptyStateIsProducedForZeroRules() {
        let model = PopoverViewModel(config: .empty, sessions: [], quarantine: nil, now: t(0))

        #expect(model.isEmpty)
        #expect(model.rows.isEmpty)
        #expect(model.banner == nil)
    }

    /// Два экземпляра одного bundle id — два остатка, каждый со своим pid. Схлопывания в одно
    /// неподписанное число нет (findings §10).
    @Test func ruleWithTwoRunningInstancesYieldsTwoRemainingTimes() throws {
        let model = PopoverViewModel(
            config: try config([rule(slack, minutes: 60)]),
            sessions: [
                session(slack, pid: 777, start: t(-100), deadline: t(600)),
                session(slack, pid: 501, start: t(-100), deadline: t(180))
            ],
            quarantine: nil,
            now: t(0)
        )

        #expect(model.rows.count == 1)
        let row = try #require(model.rows.first)
        #expect(row.instances.count == 2)
        // Порядок внутри правила — по SessionKey, то есть по pid.
        #expect(row.instances.map(\.pid) == [501, 777])
        #expect(row.instances.map(\.remainingText) == ["3:00", "10:00"])
        // Ключ сортировки правила — минимальный остаток среди его сессий.
        #expect(row.soonestRemaining == 180)
    }

    // MARK: - Редактор лимита

    /// Ноль, отрицательное, 481 и нецелое не проходят; границы диапазона проходят.
    @Test func limitEditorRejectsValuesOutsideOneToFourHundredEightyMinutes() {
        #expect(
            PopoverViewModel.limit(fromMinutesText: "0").rejection
                == .limitMinutesOutOfRange(minutes: 0)
        )
        #expect(
            PopoverViewModel.limit(fromMinutesText: "-1").rejection
                == .limitMinutesOutOfRange(minutes: -1)
        )
        #expect(
            PopoverViewModel.limit(fromMinutesText: "481").rejection
                == .limitMinutesOutOfRange(minutes: 481)
        )
        #expect(PopoverViewModel.limit(fromMinutesText: "12.5").rejection == .limitIsNotWholeMinutes)
        #expect(PopoverViewModel.limit(fromMinutesText: "").rejection == .limitIsNotWholeMinutes)
        #expect(PopoverViewModel.limit(fromMinutesText: "ten").rejection == .limitIsNotWholeMinutes)

        #expect(PopoverViewModel.limit(fromMinutesText: "1").limit == .constant(.seconds(60)))
        #expect(PopoverViewModel.limit(fromMinutesText: " 45 ").limit == .constant(.seconds(2700)))
        #expect(PopoverViewModel.limit(fromMinutesText: "480").limit == .constant(.seconds(28800)))

        // Диапазон берётся из модели, а не переписан числами в UI.
        #expect(Limit.allowedMinutes == 1...480)
    }

    // MARK: - Баннер карантина

    /// Баннер — функция состояния хранилища, а не флага, который вью ставит себе сам.
    /// Проверяется на живом `ConfigStore`, доведённом до карантина настоящим битым файлом.
    @Test func quarantinedStoreProducesTheReadOnlyBanner() throws {
        try withTemporaryDirectory { directory in
            let store = ConfigStore(dataDirectory: directory)
            try Data("{ not json".utf8).write(to: store.configURL)
            store.load()

            #expect(store.isQuarantined)
            let quarantined = PopoverViewModel(
                config: store.config,
                sessions: [],
                quarantine: store.quarantine,
                now: t(0)
            )
            let banner = try #require(quarantined.banner)
            if case .unreadableConfigFile = banner {} else {
                Issue.record("ожидался баннер о нечитаемом файле, получен \(banner)")
            }
            #expect(!banner.title.isEmpty)
            #expect(!banner.detail.isEmpty)

            // И запись действительно отказывает — баннер не декоративен.
            #expect(throws: ConfigStoreError.self) {
                try store.save(try config([rule(slack, minutes: 10)]))
            }
        }

        // Три случая причины различимы значением, а не разбором текста.
        #expect(
            PopoverBanner(.schemaVersionFromTheFuture(found: 2, supported: 1))
                == .configFromNewerBuild(found: 2, supported: 1)
        )
        #expect(
            PopoverBanner(.rejectedRule(RuleRejected(
                bundleIdentifier: slack,
                reason: .limitIsNotWholeMinutes
            ))) == .rejectedRule(bundleIdentifier: slack)
        )

        // Здоровое хранилище баннера не даёт.
        let healthy = PopoverViewModel(
            config: try config([rule(slack, minutes: 10)]),
            sessions: [],
            quarantine: nil,
            now: t(0)
        )
        #expect(healthy.banner == nil)
    }

    // MARK: - Терминальный отказ

    /// Терминальная `refused` отличима от идущего отсчёта — с уходом консент-слоя это
    /// единственное состояние отказа на правило, кроме карантина. Числовое значение
    /// `OSStatus` при этом никуда не проносится.
    @Test func refusedSessionIsDistinguishableFromCounting() throws {
        let model = PopoverViewModel(
            config: try config([rule(slack, minutes: 60), rule(telegram, minutes: 60)]),
            sessions: [
                session(slack, pid: 501, start: t(-100), deadline: t(600)),
                session(
                    telegram,
                    pid: 502,
                    start: t(-100),
                    deadline: t(-150),
                    phase: .refused(.attemptsExhausted)
                )
            ],
            quarantine: nil,
            now: t(0)
        )

        let statuses = Dictionary(
            uniqueKeysWithValues: model.rows.map { ($0.bundleIdentifier, $0.instances.map(\.status)) }
        )
        #expect(statuses[slack] == [.counting])
        #expect(statuses[telegram] == [.refused(.attemptsExhausted)])
        #expect(statuses[slack] != statuses[telegram])

        // Второй случай отказа тоже различим, и статус в него не проносится: обе сессии
        // с разными OSStatus дают одно и то же значение.
        let bySystem = PopoverInstance(
            session(slack, pid: 503, start: t(-100), deadline: t(-150), phase: .refused(.status(-1743))),
            now: t(0)
        )
        let byOtherStatus = PopoverInstance(
            session(slack, pid: 504, start: t(-100), deadline: t(-150), phase: .refused(.status(-600))),
            now: t(0)
        )
        #expect(bySystem.status == .refused(.systemRefused))
        #expect(bySystem.status == byOtherStatus.status)
        #expect(bySystem.status != .refused(.attemptsExhausted))

        // Фаза отправки — тоже не «идёт отсчёт».
        let quitting = PopoverInstance(
            session(
                slack,
                pid: 505,
                start: t(-100),
                deadline: t(-30),
                phase: .awaitingQuit(attempts: 2, lastAttemptAt: t(-5))
            ),
            now: t(0)
        )
        #expect(quitting.status == .quitting(attempts: 2))
    }

    /// Предикат красных глаз: `.counting` или `.awaitingQuit` — да, `.refused` — нет.
    /// Наивное `!activeSessions.isEmpty` держало бы глаза красными, пока жив отказавший
    /// процесс.
    @Test func refusedSessionDoesNotKeepEyesRed() {
        let counting = session(slack, pid: 501, start: t(-100), deadline: t(600))
        let quitting = session(
            slack,
            pid: 502,
            start: t(-100),
            deadline: t(-30),
            phase: .awaitingQuit(attempts: 1, lastAttemptAt: t(-30))
        )
        let refusedByAttempts = session(
            telegram,
            pid: 503,
            start: t(-100),
            deadline: t(-150),
            phase: .refused(.attemptsExhausted)
        )
        let refusedByStatus = session(
            telegram,
            pid: 504,
            start: t(-100),
            deadline: t(-150),
            phase: .refused(.status(-1743))
        )

        #expect(!PopoverViewModel.anyCountdownInFlight(in: []))
        #expect(PopoverViewModel.anyCountdownInFlight(in: [counting]))
        #expect(PopoverViewModel.anyCountdownInFlight(in: [quitting]))
        #expect(!PopoverViewModel.anyCountdownInFlight(in: [refusedByAttempts]))
        #expect(!PopoverViewModel.anyCountdownInFlight(in: [refusedByStatus]))
        #expect(!PopoverViewModel.anyCountdownInFlight(in: [refusedByAttempts, refusedByStatus]))
        // Один живой отсчёт рядом с отказом глаза зажигает.
        #expect(PopoverViewModel.anyCountdownInFlight(in: [refusedByAttempts, counting]))
    }
}

// MARK: - Фикстуры

private let slack = "com.tinyspeck.slackmacgap"
private let telegram = "ru.keepcoder.Telegram"
private let safari = "com.apple.Safari"

/// Момент `2026-08-27T13:00:00Z` плюс смещение в секундах.
private func t(_ offset: TimeInterval) -> Date {
    enabledAtFixture.addingTimeInterval(offset)
}

private func rule(_ bundleIdentifier: String, minutes: Int, enabled: Bool = true) throws -> Rule {
    try Rule(
        bundleIdentifier: bundleIdentifier,
        limit: .constant(.seconds(minutes * 60)),
        enabledAt: enabled ? enabledAtFixture : nil
    )
}

private func config(_ rules: [Rule]) -> RuleConfig {
    RuleConfig(rules)
}

private func session(
    _ bundleIdentifier: String,
    pid: pid_t,
    start: Date,
    deadline: Date,
    phase: SessionPhase = .counting
) -> ProcessSession {
    ProcessSession(
        key: SessionKey(pid: pid, startTime: start),
        bundleIdentifier: bundleIdentifier,
        deadline: deadline,
        phase: phase
    )
}
