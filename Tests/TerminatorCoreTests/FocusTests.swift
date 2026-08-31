import Foundation
import Testing

import TerminatorCore

/// Критерии приёмки TASK-007. Каждый тест синхронный: ни async, ни sleep, ни реальных часов,
/// ни `NSWorkspace`, ни настоящего каталога данных. Обе шкалы приходят параметром, поэтому
/// «Mac проспал восемь часов» — это арифметика, а не ожидание.
@Suite("Учёт фокуса")
struct FocusTests {

    // MARK: - Инвариант порядка

    /// Критерий 1. **Слить открытый спан до того, как запись удалена из таблицы сессий.**
    ///
    /// Тест назван по инварианту, а не по симптому, и ломается ровно от перестановки двух
    /// операций в реализации: слив читает таблицу, поэтому за удалением он находит пустоту,
    /// спан остаётся открытым — и мёртвый процесс продолжает накапливать. Второе ожидание
    /// ловит именно это.
    @Test func focusSpanIsFlushedBeforeProcessIsDropped() throws {
        var engine = try engineWatching([slack])
        let started = scenarioStart.addingTimeInterval(-600)
        _ = engine.handle(.reconcile(observed: [running(slack, pid: 501, start: started)]), at: now(0))
        _ = engine.handle(.frontmostChanged(front(slack, pid: 501, start: started)), at: now(0))

        _ = engine.handle(.terminated(pid: 501), at: now(60))

        #expect(engine.activeSessions.isEmpty)
        #expect(engine.focusRollup(at: now(60)).duration(for: slack, on: today) == .seconds(60))
        #expect(engine.focusRollup(at: now(600)).duration(for: slack, on: today) == .seconds(60))
    }

    /// Тот же инвариант на втором пути удаления: сессии нет в снимке сверки.
    @Test func spanIsFlushedWhenReconcileDropsTheSession() throws {
        var engine = try engineWatching([slack])
        let started = scenarioStart.addingTimeInterval(-600)
        _ = engine.handle(.reconcile(observed: [running(slack, pid: 501, start: started)]), at: now(0))
        _ = engine.handle(.frontmostChanged(front(slack, pid: 501, start: started)), at: now(0))

        _ = engine.handle(.reconcile(observed: []), at: now(60))

        #expect(engine.focusRollup(at: now(600)).duration(for: slack, on: today) == .seconds(60))
    }

    /// Третий путь: отправитель quit доложил, что процесса уже нет.
    @Test func spanIsFlushedWhenQuitReportsTheProcessIsGone() throws {
        var engine = try engineWatching([slack])
        let started = scenarioStart.addingTimeInterval(-600)
        _ = engine.handle(.reconcile(observed: [running(slack, pid: 501, start: started)]), at: now(0))
        _ = engine.handle(.frontmostChanged(front(slack, pid: 501, start: started)), at: now(0))

        _ = engine.handle(.quitOutcome(pid: 501, outcome: .notRunning), at: now(60))

        #expect(engine.focusRollup(at: now(600)).duration(for: slack, on: today) == .seconds(60))
    }

    /// Четвёртый путь: правило выключили, пока приложение было фронтмост. Спан закрывается
    /// ровно в момент правки, а заработанное до неё остаётся.
    @Test func spanIsFlushedWhenTheRuleIsDisabled() throws {
        var engine = try engineWatching([slack])
        let started = scenarioStart.addingTimeInterval(-600)
        _ = engine.handle(.reconcile(observed: [running(slack, pid: 501, start: started)]), at: now(0))
        _ = engine.handle(.frontmostChanged(front(slack, pid: 501, start: started)), at: now(0))

        _ = engine.handle(.configChanged(try config([slack], enabledAt: nil)), at: now(60))

        #expect(engine.activeSessions.isEmpty)
        #expect(engine.focusRollup(at: now(600)).duration(for: slack, on: today) == .seconds(60))
    }

    // MARK: - Границы дня

    /// Критерий 2. Спан, открытый до местной полуночи и закрытый после неё, даёт две дневные
    /// записи, сумма которых **точно** равна длине спана: граничная секунда посчитана один раз.
    @Test func spanAcrossMidnightSplitsIntoTwoDays() throws {
        var engine = try engineWatching([slack])
        let opened = utcMoment(2026, 8, 29, 23, 50)
        let closed = utcMoment(2026, 8, 30, 0, 10)

        _ = engine.handle(.frontmostChanged(front(slack, pid: 501)), at: moment(opened, awake: 0))
        _ = engine.handle(.frontmostChanged(nil), at: moment(closed, awake: 1200))

        let rollup = engine.focusRollup(at: moment(closed, awake: 1200))
        let before = rollup.duration(for: slack, on: day(2026, 8, 29))
        let after = rollup.duration(for: slack, on: day(2026, 8, 30))
        #expect(before == .seconds(600))
        #expect(after == .seconds(600))
        #expect(before + after == .seconds(1200))
    }

    /// Критерий 8, вторая половина. День перехода на зимнее время длится 25 часов, и все
    /// 25 попадают в него, а не 24 в него и час в следующий.
    @Test func dstDayOfTwentyFiveHoursIsCountedCorrectly() throws {
        var engine = try engineWatching([slack])
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        let opened = localMoment(losAngeles, 2026, 11, 1)
        let closed = localMoment(losAngeles, 2026, 11, 2)
        // Сам факт, ради которого тест существует: суток в этот день 25 часов.
        #expect(closed.timeIntervalSince(opened) == 25 * 3600)

        _ = engine.handle(
            .frontmostChanged(front(slack, pid: 501)),
            at: moment(opened, awake: 0, zone: losAngeles)
        )
        _ = engine.handle(
            .frontmostChanged(nil),
            at: moment(closed, awake: 25 * 3600, zone: losAngeles)
        )

        let rollup = engine.focusRollup(at: moment(closed, awake: 25 * 3600, zone: losAngeles))
        #expect(rollup.duration(for: slack, on: day(2026, 11, 1)) == .seconds(25 * 3600))
        #expect(rollup.duration(for: slack, on: day(2026, 11, 2)) == .zero)
    }

    /// Критерий 8, первая половина. Смена пояса не переписывает уже записанные дни.
    @Test func timeZoneChangeDoesNotRewriteRecordedDays() throws {
        var engine = try engineWatching([slack])
        let opened = utcMoment(2026, 8, 29, 10, 0)
        let closed = utcMoment(2026, 8, 29, 11, 0)

        _ = engine.handle(.frontmostChanged(front(slack, pid: 501)), at: moment(opened, awake: 0))
        _ = engine.handle(.frontmostChanged(nil), at: moment(closed, awake: 3600))
        #expect(
            engine.focusRollup(at: moment(closed, awake: 3600))
                .duration(for: slack, on: day(2026, 8, 29)) == .seconds(3600)
        )

        // Пояс уехал на UTC-11: тот же момент теперь принадлежит 28 августа. Записанный день
        // от этого не меняется — переписывать историю сменой пояса нельзя.
        let honolulu = TimeZone(secondsFromGMT: -11 * 3600)!
        let later = utcMoment(2026, 8, 29, 12, 0)
        _ = engine.handle(.dayRollover, at: moment(later, awake: 7200, zone: honolulu))

        let rollup = engine.focusRollup(at: moment(later, awake: 7200, zone: honolulu))
        #expect(rollup.duration(for: slack, on: day(2026, 8, 29)) == .seconds(3600))
        #expect(rollup.days.count == 1)
    }

    // MARK: - Паузы

    /// Критерий 3. Каждый из четырёх сигналов паузы закрывает спан, и парное возобновление
    /// открывает новый — для того, что фронтмост в тот момент.
    @Test(arguments: FocusPauseReason.allCases)
    func eachPauseSignalClosesSpanAndItsResumeOpensANewOne(_ reason: FocusPauseReason) throws {
        var engine = try engineWatching([slack])
        _ = engine.handle(.frontmostChanged(front(slack, pid: 501)), at: now(0))

        _ = engine.handle(.focusPaused(reason), at: now(60))
        // Пауза стоит: бодрствование идёт, а фокус — нет.
        #expect(engine.focusRollup(at: now(300)).duration(for: slack, on: today) == .seconds(60))

        _ = engine.handle(.focusResumed(reason), at: now(300))
        #expect(engine.focusRollup(at: now(360)).duration(for: slack, on: today) == .seconds(120))
    }

    /// Причины держатся множеством, а не флагом. Засыпание Mac поднимает две, и первое же
    /// возобновление не должно перезапускать накопление, пока машина ещё спит.
    @Test func accrualResumesOnlyWhenTheLastPauseReasonClears() throws {
        var engine = try engineWatching([slack])
        _ = engine.handle(.frontmostChanged(front(slack, pid: 501)), at: now(0))

        _ = engine.handle(.focusPaused(.displaySleep), at: now(60))
        _ = engine.handle(.focusPaused(.systemSleep), at: now(60))
        _ = engine.handle(.focusResumed(.displaySleep), at: now(120))

        // Одна причина снята, вторая нет — накопление стоит.
        #expect(engine.focusRollup(at: now(180)).duration(for: slack, on: today) == .seconds(60))

        _ = engine.handle(.focusResumed(.systemSleep), at: now(180))
        #expect(engine.focusRollup(at: now(240)).duration(for: slack, on: today) == .seconds(120))
    }

    /// Критерий 4. Восемь часов сна системы: стенные часы ушли, накопительное чтение
    /// неподвижно — ноль секунд фокуса.
    @Test func systemSleepAddsNoFocusSeconds() throws {
        var engine = try engineWatching([slack])
        _ = engine.handle(.frontmostChanged(front(slack, pid: 501)), at: now(0))

        let afterSleep = now(8 * 3600, awake: 0)
        #expect(engine.focusRollup(at: afterSleep).duration(for: slack, on: today) == .zero)

        // И после пробуждения счёт идёт с нуля, а не с восьми часов.
        _ = engine.handle(.dayRollover, at: afterSleep)
        #expect(
            engine.focusRollup(at: now(8 * 3600 + 60, awake: 60))
                .duration(for: slack, on: today) == .seconds(60)
        )
    }

    // MARK: - Кто считается наблюдаемым

    /// Критерий 5. Активация не-`.regular` приложения прозрачна: один неразорванный спан,
    /// а не два. Разрыв дал бы 20 секунд вместо 30 — потерянной оказалась бы ровно та
    /// секунда, которую системная модалка держала на себе.
    @Test func nonRegularActivationDoesNotBreakTheSpan() throws {
        var engine = try engineWatching([slack])
        _ = engine.handle(.frontmostChanged(front(slack, pid: 501)), at: now(0))
        _ = engine.handle(
            .frontmostChanged(front(notificationCentre, pid: 900, policy: .accessory)),
            at: now(10)
        )
        _ = engine.handle(.frontmostChanged(front(slack, pid: 501)), at: now(20))

        let rollup = engine.focusRollup(at: now(30))
        #expect(rollup.duration(for: slack, on: today) == .seconds(30))
        #expect(rollup.duration(for: notificationCentre, on: today) == .zero)
    }

    /// Критерий 6. Ненаблюдаемое приложение закрывает предыдущий спан и не записывает о себе
    /// ничего (DEC-005).
    @Test func unwatchedAppClosesPreviousSpanAndPersistsNothing() throws {
        var engine = try engineWatching([slack])
        _ = engine.handle(.frontmostChanged(front(slack, pid: 501)), at: now(0))
        _ = engine.handle(.frontmostChanged(front(telegram, pid: 601)), at: now(60))

        let rollup = engine.focusRollup(at: now(120))
        #expect(rollup.duration(for: slack, on: today) == .seconds(60))
        #expect(rollup.duration(for: telegram, on: today) == .zero)
        #expect(rollup.days[today].map { Array($0.keys) } == [slack])
    }

    /// Накопление идёт по включённому правилу, а не по наличию записи в таблице сессий:
    /// приложение без прочитанного `p_starttime` в таблицу не попадает, но фокус ему пишется.
    @Test func focusAccruesWithoutASessionTableEntry() throws {
        var engine = try engineWatching([slack])
        _ = engine.handle(.frontmostChanged(front(slack, pid: 501, start: nil)), at: now(0))

        #expect(engine.activeSessions.isEmpty)
        #expect(engine.focusRollup(at: now(60)).duration(for: slack, on: today) == .seconds(60))
    }

    // MARK: - Диск

    /// Критерий 7. На диске — версионированный JSON с целыми секундами, и повторные сливы не
    /// съедают субсекундный остаток: 1.5 с даёт 1, ещё 1.5 с даёт 3, а не 2.
    @Test func persistedFocusIsVersionedIntegerSecondsWithoutTruncation() throws {
        try withTemporaryDirectory { directory in
            let store = FocusStore(dataDirectory: directory)
            store.load()

            var engine = try engineWatching([slack])
            _ = engine.handle(.frontmostChanged(front(slack, pid: 501)), at: now(0))

            try store.flush(engine.focusRollup(at: now(1.5)))
            #expect(try schemaVersion(of: store.focusURL) == 1)
            #expect(try recordedSeconds(store.focusURL, on: today, for: slack) == 1)

            try store.flush(engine.focusRollup(at: now(3.0)))
            #expect(try recordedSeconds(store.focusURL, on: today, for: slack) == 3)
        }
    }

    /// Критерий 9. Слив поверх файла, в котором есть дни, которых нет в памяти, эти дни
    /// сохраняет. Это тест против «перезапуск стирает историю».
    @Test func flushPreservesDaysAlreadyOnDisk() throws {
        try withTemporaryDirectory { directory in
            let store = FocusStore(dataDirectory: directory)
            try Data(recordedFocusJSON.utf8).write(to: store.focusURL)
            store.load()

            var accrued = FocusRollup()
            accrued.add(.seconds(120), to: slack, on: day(2026, 8, 29))
            try store.flush(accrued)

            // День, которого в памяти не было, — нетронут.
            #expect(try recordedSeconds(store.focusURL, on: day(2026, 8, 1), for: telegram) == 3600)
            // День, который в памяти был, — прежние 720 плюс накопленные этим запуском 120.
            #expect(try recordedSeconds(store.focusURL, on: day(2026, 8, 29), for: slack) == 840)
        }
    }

    /// Байты файла дословно: формат — человекочитаемый контракт, и тест читает его теми же
    /// глазами, что и пользователь.
    @Test func focusFileIsHandReadable() throws {
        try withTemporaryDirectory { directory in
            let store = FocusStore(dataDirectory: directory)
            store.load()

            var accrued = FocusRollup()
            accrued.add(.seconds(3600), to: telegram, on: day(2026, 8, 1))
            accrued.add(.milliseconds(720_500), to: slack, on: day(2026, 8, 29))
            try store.flush(accrued)

            #expect(try String(contentsOf: store.focusURL, encoding: .utf8) == recordedFocusJSON)
        }
    }

    /// Файла нет — пустая свёртка, и чтение ничего на диске не создаёт.
    @Test func missingFocusFileCreatesNothing() throws {
        try withTemporaryDirectory { directory in
            let store = FocusStore(dataDirectory: directory)
            store.load()

            #expect(store.recorded == .empty)
            #expect(store.quarantine == nil)
            let entries = try directoryEntries(directory)
            #expect(entries.isEmpty)
        }
    }

    /// Версия схемы из будущего — карантин: файл не трогается байт в байт, слив отказывает,
    /// а не переписывает.
    @Test func futureSchemaVersionQuarantinesAndRefusesFlush() throws {
        try withTemporaryDirectory { directory in
            let store = FocusStore(dataDirectory: directory)
            let bytes = recordedFocusJSON.replacingOccurrences(
                of: "\"schemaVersion\" : 1",
                with: "\"schemaVersion\" : 2"
            )
            try Data(bytes.utf8).write(to: store.focusURL)
            store.load()

            #expect(store.quarantine == .schemaVersionFromTheFuture(found: 2, supported: 1))

            var accrued = FocusRollup()
            accrued.add(.seconds(120), to: slack, on: day(2026, 8, 29))
            #expect(throws: FocusStoreError.self) { try store.flush(accrued) }
            #expect(try String(contentsOf: store.focusURL, encoding: .utf8) == bytes)
        }
    }

    /// Испорченные байты — тот же карантин, и по той же причине: восполнить историю нечем.
    @Test func undecodableBytesQuarantineTheStore() throws {
        try withTemporaryDirectory { directory in
            let store = FocusStore(dataDirectory: directory)
            try Data("{ not json".utf8).write(to: store.focusURL)
            store.load()

            #expect(store.isQuarantined)
            var accrued = FocusRollup()
            accrued.add(.seconds(120), to: slack, on: day(2026, 8, 29))
            #expect(throws: FocusStoreError.self) { try store.flush(accrued) }
        }
    }
}

// MARK: - Фикстуры

private let slack = "com.tinyspeck.slackmacgap"
private let telegram = "ru.keepcoder.Telegram"
private let notificationCentre = "com.apple.UserNotificationCenter"

private let utc = TimeZone(secondsFromGMT: 0)!

/// Начало сценария: 29 августа 2026, 10:00 UTC. Тесты не читают реальные часы вообще.
private let scenarioStart = utcMoment(2026, 8, 29, 10, 0)

/// Календарный день, которому принадлежит `scenarioStart` в UTC.
private let today = DayKey(year: 2026, month: 8, day: 29)

/// Произвольная точка на шкале бодрствования: смысл имеет только разность двух моментов.
private let awakeOrigin: TimeInterval = 500_000

private func utcMoment(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int = 0,
    _ minute: Int = 0
) -> Date {
    localMoment(TimeZone(secondsFromGMT: 0)!, year, month, day, hour, minute)
}

private func localMoment(
    _ zone: TimeZone,
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int = 0,
    _ minute: Int = 0
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar.date(
        from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    )!
}

private func day(_ year: Int, _ month: Int, _ day: Int) -> DayKey {
    DayKey(year: year, month: month, day: day)
}

/// Момент через `elapsed` секунд после начала сценария.
///
/// По умолчанию бодрствование идёт вровень со стенными часами — машина не спит. Тест сна
/// передаёт `awake` отдельно: стенные часы уходят на восемь часов, накопительное чтение стоит.
private func now(_ elapsed: TimeInterval, awake: TimeInterval? = nil) -> Now {
    moment(scenarioStart.addingTimeInterval(elapsed), awake: awake ?? elapsed)
}

private func moment(_ wall: Date, awake: TimeInterval, zone: TimeZone = utc) -> Now {
    Now(
        wall: wall,
        awake: AwakeInstant(sinceOrigin: .seconds(awakeOrigin + awake)),
        timeZone: zone
    )
}

private func config(_ identifiers: [String], enabledAt: Date?) throws -> RuleConfig {
    RuleConfig(
        try identifiers.map {
            try Rule(
                bundleIdentifier: $0,
                // Восемь часов: дедлайн в этих сценариях не наступает, отсчёт фокусу не мешает.
                limit: .constant(.seconds(480 * 60)),
                enabledAt: enabledAt
            )
        }
    )
}

private func engineWatching(_ identifiers: [String]) throws -> WatchEngine {
    WatchEngine(config: try config(identifiers, enabledAt: scenarioStart.addingTimeInterval(-3600)))
}

private func front(
    _ bundleIdentifier: String?,
    pid: pid_t,
    start: Date? = nil,
    policy: ProcessActivationPolicy = .regular
) -> FrontmostApp {
    FrontmostApp(
        pid: pid,
        bundleIdentifier: bundleIdentifier,
        startTime: start,
        activationPolicy: policy
    )
}

private func running(_ bundleIdentifier: String, pid: pid_t, start: Date) -> ObservedProcess {
    ObservedProcess(
        pid: pid,
        bundleIdentifier: bundleIdentifier,
        startTime: start,
        activationPolicy: .regular
    )
}

/// Секунды из файла, прочитанные независимо от кодека продукта.
private func recordedSeconds(_ url: URL, on day: DayKey, for bundleIdentifier: String) throws -> Int? {
    let bytes = try Data(contentsOf: url)
    let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
    let days = root?["days"] as? [String: Any]
    let entries = days?[day.description] as? [String: Any]
    return entries?[bundleIdentifier] as? Int
}

/// Файл фокуса, набранный руками: два дня, два приложения, целые секунды.
private let recordedFocusJSON = """
{
  "days" : {
    "2026-08-01" : {
      "ru.keepcoder.Telegram" : 3600
    },
    "2026-08-29" : {
      "com.tinyspeck.slackmacgap" : 720
    }
  },
  "schemaVersion" : 1
}
"""
