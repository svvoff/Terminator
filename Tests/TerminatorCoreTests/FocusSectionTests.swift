import Foundation
import Testing

import TerminatorCore

/// Критерии приёмки TASK-101, фаза A: какую свёртку сводить и какое из трёх состояний показать.
/// Каждый тест синхронный: ни sleep, ни реальных часов, ни файловой системы. Обе свёртки
/// собираются в памяти, момент и пояс приходят параметром.
///
/// Сила утверждений не зависит от порядка обхода `Set` и `Dictionary`: строки сводки
/// упорядочены полностью, а там, где строка выбирается, она выбирается по идентификатору.
@Suite("Секция фокуса")
struct FocusSectionTests {

    // MARK: - Карантин

    /// Карантин — `unreadable` при данных в **обеих** свёртках. В карантине `recorded` пуст на
    /// деле, но секция не смеет на это полагаться: если бы решала пустота, а не карантин,
    /// данные здесь дали бы сводку.
    ///
    /// Контрольный прогон — те же входы без карантина дают сводку с данными из обеих свёрток:
    /// иначе `unreadable` здесь нельзя было бы отличить от «данных не хватило».
    @Test func quarantineShowsUnreadableEvenWithData() throws {
        var recorded = FocusRollup()
        recorded.add(.seconds(600), to: telegram, on: day(2026, 9, 15))
        var accrued = FocusRollup()
        accrued.add(.seconds(30), to: telegram, on: day(2026, 9, 17))
        let config = try rules([telegram], enabled: true)

        for failure: FocusLoadFailure in [
            .undecodableBytes(message: "unexpected character at offset 0"),
            .schemaVersionFromTheFuture(found: 2, supported: 1),
        ] {
            let section = FocusSection(
                recorded: recorded,
                accrued: accrued,
                quarantine: failure,
                config: config,
                now: septemberSeventeenth
            )
            #expect(section == .unreadable)
        }

        let control = FocusSection(
            recorded: recorded,
            accrued: accrued,
            quarantine: nil,
            config: config,
            now: septemberSeventeenth
        )
        guard case .summary(let summary) = control else {
            Issue.record("без карантина те же данные обязаны дать сводку, получено \(control)")
            return
        }
        let row = try #require(summary.rows.first { $0.bundleIdentifier == telegram })
        #expect(row.total == .seconds(630))
    }

    // MARK: - Скрытие

    /// Нет строк — секция скрыта. Три входа без строк: всё пусто; данные только вне окна;
    /// записанный день окна без единого приложения. Последний даёт знаменатель `1 of 7`, но
    /// строк у него нет — показывать нечего.
    @Test func noRowsHidesTheSection() {
        let empty = FocusSection(
            recorded: .empty,
            accrued: .empty,
            quarantine: nil,
            config: .empty,
            now: septemberSeventeenth
        )
        #expect(empty == .hidden)

        var outsideWindow = FocusRollup()
        outsideWindow.add(.seconds(600), to: telegram, on: day(2026, 9, 10))
        let onlyOutside = FocusSection(
            recorded: outsideWindow,
            accrued: .empty,
            quarantine: nil,
            config: .empty,
            now: septemberSeventeenth
        )
        #expect(onlyOutside == .hidden)

        let emptyDayKey = FocusSection(
            recorded: FocusRollup(days: [day(2026, 9, 14): [:]]),
            accrued: .empty,
            quarantine: nil,
            config: .empty,
            now: septemberSeventeenth
        )
        #expect(emptyDayKey == .hidden)
    }

    /// Выключенное правило без данных строки не даёт, и секция скрыта. Контроль — то же
    /// правило включённым даёт сводку с одной строкой: иначе `hidden` здесь нельзя было бы
    /// отличить от секции, которая правил не читает вовсе.
    @Test func disabledRuleAloneDoesNotShowTheSection() throws {
        let disabled = FocusSection(
            recorded: .empty,
            accrued: .empty,
            quarantine: nil,
            config: try rules([safari], enabled: false),
            now: septemberSeventeenth
        )
        #expect(disabled == .hidden)

        let enabled = FocusSection(
            recorded: .empty,
            accrued: .empty,
            quarantine: nil,
            config: try rules([safari], enabled: true),
            now: septemberSeventeenth
        )
        guard case .summary(let summary) = enabled else {
            Issue.record("включённое правило обязано дать строку, получено \(enabled)")
            return
        }
        #expect(summary.rows.map(\.bundleIdentifier) == [safari])
    }

    // MARK: - Сумма свёрток

    /// Сводится сумма: записанное плюс ещё не слитое на диск. В `recorded` — прошлый день и
    /// 100 с сегодня, в `accrued` — 30 с сегодня. Сегодня — 130 с, прошлый день — целиком.
    ///
    /// Каждое слагаемое в одиночку даёт другое: только `recorded` — 100 с сегодня; только
    /// `accrued` — `nil` на прошлом дне.
    @Test func sectionAddsUnflushedAccrualToRecordedHistory() throws {
        var recorded = FocusRollup()
        recorded.add(.seconds(600), to: telegram, on: day(2026, 9, 15))
        recorded.add(.seconds(100), to: telegram, on: day(2026, 9, 17))
        var accrued = FocusRollup()
        accrued.add(.seconds(30), to: telegram, on: day(2026, 9, 17))

        let section = FocusSection(
            recorded: recorded,
            accrued: accrued,
            quarantine: nil,
            config: .empty,
            now: septemberSeventeenth
        )
        guard case .summary(let summary) = section else {
            Issue.record("ожидалась сводка, получено \(section)")
            return
        }

        let fifteenth = try #require(summary.days.firstIndex(of: day(2026, 9, 15)))
        let today = try #require(summary.days.firstIndex(of: day(2026, 9, 17)))
        let row = try #require(summary.rows.first { $0.bundleIdentifier == telegram })
        #expect(row.perDay[today] == .seconds(130))
        #expect(row.perDay[fifteenth] == .seconds(600))
        #expect(row.total == .seconds(730))
        #expect(summary.recordedDayCount == 2)
    }

    /// Сегодняшнего дня в файле нет — первый слив дня ещё не прошёл, — а в накопленном он есть.
    /// Такой день записан: он входит в `recordedDayCount`, и его ячейка — не `nil`.
    @Test func accrualOnADayMissingFromTheFileCountsAsRecorded() throws {
        var recorded = FocusRollup()
        recorded.add(.seconds(600), to: telegram, on: day(2026, 9, 15))
        var accrued = FocusRollup()
        accrued.add(.seconds(30), to: telegram, on: day(2026, 9, 17))
        #expect(recorded.days[day(2026, 9, 17)] == nil)

        let section = FocusSection(
            recorded: recorded,
            accrued: accrued,
            quarantine: nil,
            config: .empty,
            now: septemberSeventeenth
        )
        guard case .summary(let summary) = section else {
            Issue.record("ожидалась сводка, получено \(section)")
            return
        }

        let today = try #require(summary.days.firstIndex(of: day(2026, 9, 17)))
        let row = try #require(summary.rows.first { $0.bundleIdentifier == telegram })
        #expect(summary.recordedDayCount == 2)
        #expect(summary.recordedDaysText == "2 of 7 days recorded")
        #expect(row.perDay[today] == .seconds(30))
    }

    /// Сводка секции — ровно `FocusSummary` суммы свёрток с тем же конфигом и моментом.
    ///
    /// Входы подобраны так, чтобы подмена любого аргумента меняла сводку: сводка одного
    /// `recorded` и сводка одного `accrued` от неё отличаются, а включённое правило без данных
    /// даёт строку, только если конфиг дошёл до сводки.
    @Test func sectionEqualsSummaryOfCombinedRollup() throws {
        var recorded = FocusRollup()
        recorded.add(.seconds(2340), to: telegram, on: day(2026, 9, 14))
        recorded.add(.seconds(11), to: finder, on: day(2026, 9, 14))
        recorded.add(.seconds(900), to: xcode, on: day(2026, 9, 16))
        recorded.add(.seconds(120), to: telegram, on: day(2026, 9, 17))
        var accrued = FocusRollup()
        accrued.add(.seconds(45) + .milliseconds(500), to: telegram, on: day(2026, 9, 17))
        accrued.add(.seconds(300), to: xcode, on: day(2026, 9, 17))

        let config = RuleConfig([
            try Rule(
                bundleIdentifier: safari,
                limit: .constant(.seconds(600)),
                enabledAt: instant(utc, 2026, 9, 1, 9, 0)
            ),
            try Rule(bundleIdentifier: notes, limit: .constant(.seconds(600)), enabledAt: nil),
        ])

        let section = FocusSection(
            recorded: recorded,
            accrued: accrued,
            quarantine: nil,
            config: config,
            now: septemberSeventeenth
        )
        let expected = FocusSummary(
            rollup: recorded.adding(accrued),
            config: config,
            now: septemberSeventeenth
        )
        #expect(section == .summary(expected))

        guard case .summary(let summary) = section else {
            Issue.record("ожидалась сводка, получено \(section)")
            return
        }
        #expect(summary == expected)
        #expect(summary.rows.map(\.bundleIdentifier) == [telegram, xcode, finder, safari])

        // Каждое слагаемое в одиночку и пустой конфиг дают другую сводку.
        #expect(summary != FocusSummary(rollup: recorded, config: config, now: septemberSeventeenth))
        #expect(summary != FocusSummary(rollup: accrued, config: config, now: septemberSeventeenth))
        #expect(summary != FocusSummary(
            rollup: recorded.adding(accrued),
            config: .empty,
            now: septemberSeventeenth
        ))
    }
}

// MARK: - Хелперы

private let telegram = "ru.keepcoder.Telegram"
private let safari = "com.apple.Safari"
private let finder = "com.apple.finder"
private let xcode = "com.apple.dt.Xcode"
private let notes = "com.apple.Notes"

private let utc = TimeZone(secondsFromGMT: 0)!

/// Сегодня: 17 сентября 2026, 14:00 UTC. Окно — 09-11 … 09-17.
private let septemberSeventeenth = moment(utc, 2026, 9, 17, 14, 0)

private func day(_ year: Int, _ month: Int, _ day: Int) -> DayKey {
    DayKey(year: year, month: month, day: day)
}

/// Момент по стенным часам в явном поясе. Реальные часы не читаются.
private func instant(
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

/// `Now` из явных частей. Шкала бодрствования секции не нужна — момент на ней нулевой.
private func moment(
    _ zone: TimeZone,
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int = 0,
    _ minute: Int = 0
) -> Now {
    Now(
        wall: instant(zone, year, month, day, hour, minute),
        awake: AwakeInstant(sinceOrigin: .zero),
        timeZone: zone
    )
}

/// Конфиг из правил с одинаковым состоянием включённости и лимитом 10 минут.
private func rules(_ identifiers: [String], enabled: Bool) throws -> RuleConfig {
    let enabledAt: Date? = enabled ? instant(utc, 2026, 9, 1, 9, 0) : nil
    return RuleConfig(try identifiers.map {
        try Rule(bundleIdentifier: $0, limit: .constant(.seconds(600)), enabledAt: enabledAt)
    })
}
