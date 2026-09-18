import Foundation
import Testing

import TerminatorCore

/// Критерии приёмки TASK-108. Каждый тест синхронный: ни sleep, ни реальных часов, ни файловой
/// системы. Свёртка собирается в памяти, момент и пояс приходят параметром, поэтому «неделя
/// через переход на летнее время» — это другой `Now`, а не ожидание.
@Suite("Сводка фокуса")
struct FocusSummaryTests {

    // MARK: - Окно

    /// Критерий 1. Окно — ровно семь календарных дней, последний — сегодняшний, по возрастанию.
    /// Сегодня выбрано так, чтобы окно пересекало границу месяца.
    ///
    /// Второй момент — ровно местная полночь: якорь окна должен быть началом **сегодняшнего**
    /// дня. Сдвиг якоря хоть на секунду назад в полночь попадает во вчера и уводит всё окно на
    /// сутки, а в полдень неразличим.
    @Test func windowIsSevenDaysEndingToday() {
        let summary = FocusSummary(
            rollup: .empty,
            config: .empty,
            now: moment(utc, 2026, 9, 3, 12, 0)
        )

        #expect(FocusSummary.dayCount == 7)
        #expect(summary.days == [
            day(2026, 8, 28), day(2026, 8, 29), day(2026, 8, 30), day(2026, 8, 31),
            day(2026, 9, 1), day(2026, 9, 2), day(2026, 9, 3),
        ])
        #expect(summary.days.last == day(2026, 9, 3))
        #expect(zip(summary.days, summary.days.dropFirst()).allSatisfy { $0 < $1 })

        let atMidnight = FocusSummary(
            rollup: .empty,
            config: .empty,
            now: moment(utc, 2026, 9, 17, 0, 0)
        )
        #expect(atMidnight.days == [
            day(2026, 9, 11), day(2026, 9, 12), day(2026, 9, 13), day(2026, 9, 14),
            day(2026, 9, 15), day(2026, 9, 16), day(2026, 9, 17),
        ])
        #expect(atMidnight.days.last == day(2026, 9, 17))
    }

    /// Критерий 9. Окно через переход на летнее и на зимнее время — в поясах с DST. Три
    /// сценария, каждый ловит свой неверный шаг:
    ///
    /// - Берлин, весна: шаг фиксированными секундами хоть от `now`, хоть от начала дня даёт
    ///   `03-23 … 03-28, 03-30` — 29 марта длится 23 часа и выпадает;
    /// - Берлин, осень: шаг секундами от `now` даёт два `10-25` подряд — 25 октября длится
    ///   25 часов;
    /// - Нуук, весна: переход в 23:00 → 00:00, и 23:00–23:59 28 марта не существует. Шаг
    ///   календарными сутками от `now.wall` (23:30), а не от начала дня, попадает в
    ///   несуществующее время, сдвигается в 29 марта и даёт `03-29, 03-29, 03-30 … 04-03`.
    ///   В Берлине переход в 02:00 стенное время через полночь не переносит, и этот шаг там
    ///   проходит.
    ///
    /// Ожидания — литералами.
    @Test func windowCrossesDaylightSavingCorrectly() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        let nuuk = try #require(TimeZone(identifier: "America/Nuuk"))

        // Предпосылка: переходы на этой машине ровно там, где их ждут ожидания ниже; иначе
        // окно не пересекало бы переход и тест ничего не проверял бы.
        // 01:00 UTC — это 02:00 CET весной и 03:00 CEST осенью в Берлине и 23:00 по Нууку
        // 28 марта.
        try #require(
            berlin.nextDaylightSavingTimeTransition(after: instant(utc, 2026, 3, 28))
                == instant(utc, 2026, 3, 29, 1, 0)
        )
        try #require(
            berlin.nextDaylightSavingTimeTransition(after: instant(utc, 2026, 10, 24))
                == instant(utc, 2026, 10, 25, 1, 0)
        )
        try #require(
            nuuk.nextDaylightSavingTimeTransition(after: instant(utc, 2026, 3, 28))
                == instant(utc, 2026, 3, 29, 1, 0)
        )

        let spring = FocusSummary(
            rollup: .empty,
            config: .empty,
            now: moment(berlin, 2026, 3, 30, 0, 30)
        )
        #expect(spring.days == [
            day(2026, 3, 24), day(2026, 3, 25), day(2026, 3, 26), day(2026, 3, 27),
            day(2026, 3, 28), day(2026, 3, 29), day(2026, 3, 30),
        ])

        let autumn = FocusSummary(
            rollup: .empty,
            config: .empty,
            now: moment(berlin, 2026, 10, 25, 23, 30)
        )
        #expect(autumn.days == [
            day(2026, 10, 19), day(2026, 10, 20), day(2026, 10, 21), day(2026, 10, 22),
            day(2026, 10, 23), day(2026, 10, 24), day(2026, 10, 25),
        ])

        let midnightTransition = FocusSummary(
            rollup: .empty,
            config: .empty,
            now: moment(nuuk, 2026, 4, 3, 23, 30)
        )
        #expect(midnightTransition.days == [
            day(2026, 3, 28), day(2026, 3, 29), day(2026, 3, 30), day(2026, 3, 31),
            day(2026, 4, 1), day(2026, 4, 2), day(2026, 4, 3),
        ])
    }

    // MARK: - nil против нуля

    /// Критерий 2. День окна, которого нет в свёртке, — `nil` в **каждой** строке, и ячейка
    /// рисует тире, а не ноль.
    @Test func missingDayIsNilNotZero() throws {
        // Окно 09-11 … 09-17; записаны только 09-12, 09-14 и 09-16, а четыре дня окна —
        // 09-11, 09-13, 09-15 и 09-17 — в свёртке отсутствуют.
        var rollup = FocusRollup()
        rollup.add(.seconds(600), to: telegram, on: day(2026, 9, 12))
        rollup.add(.seconds(120), to: safari, on: day(2026, 9, 12))
        rollup.add(.seconds(300), to: telegram, on: day(2026, 9, 14))
        rollup.add(.seconds(240), to: safari, on: day(2026, 9, 16))

        let summary = FocusSummary(rollup: rollup, config: .empty, now: septemberSeventeenth)

        let missing = try #require(summary.days.firstIndex(of: day(2026, 9, 13)))
        #expect(summary.rows.count == 2)
        for row in summary.rows {
            #expect(row.perDay[missing] == nil)
            #expect(row.perDay[4] == nil)          // 09-15
            #expect(row.perDay[missing] != .zero)
        }
        #expect(FocusSummary.cellText(nil) == "\u{2014}")
        #expect(FocusSummary.cellText(nil).unicodeScalars.map(\.value) == [0x2014])
    }

    /// Критерий 3. День записан, у приложения в нём записи нет — `.zero`, не `nil`, и ячейка
    /// рисует `0`, не тире.
    @Test func recordedDayWithoutAppIsZero() throws {
        var rollup = FocusRollup()
        rollup.add(.seconds(600), to: telegram, on: day(2026, 9, 14))
        rollup.add(.seconds(300), to: safari, on: day(2026, 9, 15))

        let summary = FocusSummary(rollup: rollup, config: .empty, now: septemberSeventeenth)

        let fourteenth = try #require(summary.days.firstIndex(of: day(2026, 9, 14)))
        let safariRow = try #require(summary.rows.first { $0.bundleIdentifier == safari })
        let cell = safariRow.perDay[fourteenth]

        #expect(cell != nil)
        #expect(cell == .zero)
        #expect(FocusSummary.cellText(cell) == "0")
        #expect(FocusSummary.cellText(cell) != "\u{2014}")
    }

    /// Ключ дня с пустым словарём приложений — день записан: не только в знаменателе, но и в
    /// ячейках. С диска такой снимок не приходит (`add` пустых дней не создаёт), но определение
    /// буквальное — «ключ есть».
    @Test func emptyDayKeyShowsZeroInCells() throws {
        let rollup = FocusRollup(days: [day(2026, 9, 14): [:]])
        let config = try rules([safari], enabled: true)

        let summary = FocusSummary(rollup: rollup, config: config, now: septemberSeventeenth)

        #expect(summary.days[3] == day(2026, 9, 14))
        let row = try #require(summary.rows.first { $0.bundleIdentifier == safari })
        #expect(row.perDay[3] == .zero)
        #expect(row.perDay == [nil, nil, nil, .zero, nil, nil, nil])
        #expect(row.perDay.map(FocusSummary.cellText) == [
            "\u{2014}", "\u{2014}", "\u{2014}", "0", "\u{2014}", "\u{2014}", "\u{2014}",
        ])
        #expect(summary.recordedDaysText == "1 of 7 days recorded")
    }

    // MARK: - Форматирование

    /// Критерий 4. 11 с: ячейка `<1`, итог точный — `11 s`. Разные единицы — намеренно.
    @Test func subMinuteRendersAsLessThanOne() throws {
        var rollup = FocusRollup()
        rollup.add(.seconds(11), to: finder, on: day(2026, 9, 14))

        let summary = FocusSummary(rollup: rollup, config: .empty, now: septemberSeventeenth)

        let row = try #require(summary.rows.first)
        let fourteenth = try #require(summary.days.firstIndex(of: day(2026, 9, 14)))
        #expect(row.total == .seconds(11))
        #expect(FocusSummary.cellText(row.perDay[fourteenth]) == "<1")
        #expect(FocusSummary.totalText(row.total) == "11 s")
    }

    /// Субсекундное значение доходит до итога сводки целиком: 500 мс — итог ровно 500 мс,
    /// ячейка `<1`, итог `<1 s`, а не ноль. В памяти такие значения возможны: TASK-101
    /// складывает записанное с ещё не сброшенным на диск.
    @Test func subSecondTotalIsNotZero() throws {
        let rollup = FocusRollup(days: [day(2026, 9, 14): [finder: .milliseconds(500)]])

        let summary = FocusSummary(rollup: rollup, config: .empty, now: septemberSeventeenth)

        let row = try #require(summary.rows.first { $0.bundleIdentifier == finder })
        #expect(row.total == .milliseconds(500))
        #expect(FocusSummary.cellText(row.perDay[3]) == "<1")
        #expect(FocusSummary.totalText(row.total) == "<1 s")
    }

    /// Остаток мельче миллисекунды доживает до итога: накопление идёт с монотонных часов, и
    /// остаток у дня наносекундный. Суммирование, округляющее день до целых миллисекунд,
    /// схлопнуло бы половину миллисекунды в ноль — и два таких дня дали бы `0 s` на ненулевом
    /// итоге.
    @Test func subMillisecondRemainderSurvivesSummation() throws {
        var rollup = FocusRollup()
        rollup.add(.microseconds(500), to: finder, on: day(2026, 9, 12))
        rollup.add(.microseconds(500), to: finder, on: day(2026, 9, 16))

        let summary = FocusSummary(rollup: rollup, config: .empty, now: septemberSeventeenth)

        let row = try #require(summary.rows.first { $0.bundleIdentifier == finder })
        #expect(row.total == .milliseconds(1))
        #expect(row.perDay[1] == .microseconds(500))
        #expect(FocusSummary.cellText(row.perDay[1]) == "<1")
        #expect(FocusSummary.totalText(row.total) == "<1 s")
    }

    /// Критерий 5. Минуты и итоги усекаются вниз и никогда не округляются вверх.
    @Test func cellsTruncateDownNeverUp() throws {
        #expect(FocusSummary.cellText(.seconds(115)) == "1")
        #expect(FocusSummary.cellText(.seconds(119) + .milliseconds(999)) == "1")
        #expect(FocusSummary.cellText(.seconds(12_300)) == "205")
        #expect(FocusSummary.cellText(.seconds(60)) == "1")
        #expect(FocusSummary.cellText(.milliseconds(59_999)) == "<1")
        #expect(FocusSummary.cellText(.milliseconds(500)) == "<1")
        // Нижний край: наименьшее практически представимое ненулевое значение — тоже `<1`,
        // а не `0`. Ноль в ячейке означает «день записан, записи нет», и на ненулевой
        // длительности он был бы ложью.
        #expect(FocusSummary.cellText(.nanoseconds(1)) == "<1")

        #expect(FocusSummary.totalText(.seconds(3599)) == "59 m")
        #expect(FocusSummary.totalText(.seconds(12_359)) == "3 h 25 m")

        // То же через сводку: 115 с в дне окна — ячейка `1`, итог `1 m`.
        var rollup = FocusRollup()
        rollup.add(.seconds(115), to: telegram, on: day(2026, 9, 17))
        let summary = FocusSummary(rollup: rollup, config: .empty, now: septemberSeventeenth)
        let row = try #require(summary.rows.first)
        #expect(FocusSummary.cellText(row.perDay[6]) == "1")
        #expect(FocusSummary.totalText(row.total) == "1 m")
    }

    /// Итог строки: каждая строка таблицы единиц и переходы между соседними единицами.
    @Test func totalTextCoversEveryUnit() {
        #expect(FocusSummary.totalText(.zero) == "0 s")
        #expect(FocusSummary.totalText(.milliseconds(500)) == "<1 s")
        // Нижний край: наименьшее практически представимое ненулевое значение — `<1 s`.
        // `0 s` здесь показал бы ноль на ненулевом итоге.
        #expect(FocusSummary.totalText(.nanoseconds(1)) == "<1 s")
        #expect(FocusSummary.totalText(.seconds(1)) == "1 s")
        #expect(FocusSummary.totalText(.seconds(11)) == "11 s")
        #expect(FocusSummary.totalText(.seconds(59)) == "59 s")
        #expect(FocusSummary.totalText(.seconds(59) + .milliseconds(999)) == "59 s")
        #expect(FocusSummary.totalText(.seconds(60)) == "1 m")
        #expect(FocusSummary.totalText(.seconds(3599)) == "59 m")
        #expect(FocusSummary.totalText(.seconds(3600)) == "1 h 0 m")
        #expect(FocusSummary.totalText(.seconds(3659)) == "1 h 0 m")
        #expect(FocusSummary.totalText(.seconds(12_359)) == "3 h 25 m")
        #expect(FocusSummary.totalText(.seconds(187_800)) == "52 h 10 m")
        // Верхний край таблицы. Потолок недели — 168 ч на одном приложении, и крупнейшая
        // единица там всё ещё час: третьей ступени «дни» в таблице нет, `100 h 0 m` не
        // превращается в `4 d 4 h`.
        #expect(FocusSummary.totalText(.seconds(360_000)) == "100 h 0 m")
        #expect(FocusSummary.totalText(.seconds(604_740)) == "167 h 59 m")
    }

    // MARK: - Набор строк

    /// Критерий 6. История без правила: `com.apple.finder` с 11 с на 2026-09-14 при конфиге,
    /// где его нет, — строка есть. Случай живой, в файле автора он лежит прямо сейчас.
    @Test func rowsIncludeHistoryWithoutARule() throws {
        var rollup = FocusRollup()
        rollup.add(.seconds(11), to: finder, on: day(2026, 9, 14))
        rollup.add(.seconds(2340), to: telegram, on: day(2026, 9, 14))

        let config = try rules([telegram], enabled: true)
        #expect(config.rule(for: finder) == nil)

        let summary = FocusSummary(rollup: rollup, config: config, now: septemberSeventeenth)

        let finderRow = try #require(summary.rows.first { $0.bundleIdentifier == finder })
        #expect(finderRow.total == .seconds(11))
        #expect(summary.rows.map(\.bundleIdentifier) == [telegram, finder])
    }

    /// Критерий 7. Включённое правило без данных — строка есть: `nil` на незаписанных днях,
    /// `.zero` на записанных, итог `.zero` и `0 s`.
    @Test func rowsIncludeEnabledRuleWithNoData() throws {
        // Записаны 09-12 и 09-16 — данными другого приложения.
        var rollup = FocusRollup()
        rollup.add(.seconds(600), to: telegram, on: day(2026, 9, 12))
        rollup.add(.seconds(900), to: telegram, on: day(2026, 9, 16))

        let config = try rules([safari], enabled: true)
        let summary = FocusSummary(rollup: rollup, config: config, now: septemberSeventeenth)

        let row = try #require(summary.rows.first { $0.bundleIdentifier == safari })
        #expect(row.perDay == [nil, .zero, nil, nil, nil, .zero, nil])
        #expect(row.perDay.count == FocusSummary.dayCount)
        #expect(row.total == .zero)
        #expect(FocusSummary.totalText(row.total) == "0 s")
        #expect(row.perDay.map(FocusSummary.cellText) == [
            "\u{2014}", "0", "\u{2014}", "\u{2014}", "\u{2014}", "0", "\u{2014}",
        ])

        // Включено ⇔ `enabledAt != nil`: сводка читает его как флаг (DEC-001), а не как дату,
        // поэтому правило, включённое позже `now`, даёт такую же строку.
        let enabledLater = RuleConfig([
            try Rule(
                bundleIdentifier: safari,
                limit: .constant(.seconds(600)),
                enabledAt: instant(utc, 2026, 9, 20, 9, 0)
            )
        ])
        let laterSummary = FocusSummary(
            rollup: rollup,
            config: enabledLater,
            now: septemberSeventeenth
        )
        let laterRow = try #require(laterSummary.rows.first { $0.bundleIdentifier == safari })
        #expect(laterRow.perDay == [nil, .zero, nil, nil, nil, .zero, nil])
        #expect(laterRow.total == .zero)
    }

    /// Критерий 7, вторая половина края: у включённого правила данные **есть**, но лежат целиком
    /// вне окна. Строка остаётся — её даёт включённость, — а числа в ней берутся только из окна:
    /// семь прочерков и нулевой итог. Итог, подобранный по всей свёртке, нарисовал бы `5 m` на
    /// неделе, в которой приложение не было впереди ни разу, и это видимое неверное число.
    ///
    /// Выключенного двойника этого случая закрывает `rowsExcludeDisabledRuleWithoutData`: там
    /// строки нет вовсе. Здесь строка есть, и окно обязано остаться единственным источником её
    /// чисел.
    @Test func enabledRuleIgnoresDataOutsideTheWindow() throws {
        // Окно 09-11 … 09-17; единственная запись Safari — 300 с на 09-04, за краем окна.
        var rollup = FocusRollup()
        rollup.add(.seconds(300), to: safari, on: day(2026, 9, 4))

        let config = try rules([safari], enabled: true)
        let summary = FocusSummary(rollup: rollup, config: config, now: septemberSeventeenth)

        #expect(!summary.days.contains(day(2026, 9, 4)))
        #expect(summary.rows.map(\.bundleIdentifier) == [safari])
        let row = try #require(summary.rows.first { $0.bundleIdentifier == safari })
        #expect(row.perDay == [nil, nil, nil, nil, nil, nil, nil])
        #expect(row.total == .zero)
        #expect(FocusSummary.totalText(row.total) == "0 s")
        #expect(summary.recordedDayCount == 0)
    }

    /// Критерий 7, край: в окне не записано **ни одного** дня. Это первая неделя после
    /// установки и любой перерыв длиной в неделю. Строки включённых правил обязаны остаться —
    /// вместо пустой секции строка со всеми `—` и нулевым итогом. Исчезнувшая строка была бы
    /// потерей правила ровно на первом открытии.
    @Test func enabledRulesSurviveAnEmptyWindow() throws {
        let config = try rules([safari, telegram], enabled: true)

        let summary = FocusSummary(rollup: .empty, config: config, now: septemberSeventeenth)

        #expect(summary.rows.count == 2)
        #expect(summary.rows.map(\.bundleIdentifier) == [safari, telegram])
        for row in summary.rows {
            #expect(row.perDay.count == FocusSummary.dayCount)
            #expect(row.perDay == [nil, nil, nil, nil, nil, nil, nil])
            #expect(row.total == .zero)
            #expect(FocusSummary.totalText(row.total) == "0 s")
            #expect(
                row.perDay.map(FocusSummary.cellText)
                    == Array(repeating: "\u{2014}", count: FocusSummary.dayCount)
            )
        }
        #expect(summary.recordedDayCount == 0)
        #expect(summary.recordedDaysText == "0 of 7 days recorded")

        // Две строки пустой недели различаются **только** идентификатором: ячейки и итог у них
        // совпадают до символа. Равенство строки обязано это различать, иначе на свежей неделе
        // все строки таблицы оказались бы равны между собой.
        #expect(summary.rows[0] != summary.rows[1])
    }

    /// Набор строк ничем не ограничен сверху: сколько приложений записано в окне, столько и
    /// строк. Двенадцать — больше любого молчаливого «топа», который отрезал бы хвост.
    @Test func rowSetIsNotTruncated() {
        let identifiers = (1...12).map { "com.example.app\($0)" }
        var rollup = FocusRollup()
        for (index, identifier) in identifiers.enumerated() {
            rollup.add(.seconds(60 * (index + 1)), to: identifier, on: day(2026, 9, 14))
        }

        let summary = FocusSummary(rollup: rollup, config: .empty, now: septemberSeventeenth)

        #expect(summary.rows.count == 12)
        #expect(Set(summary.rows.map(\.bundleIdentifier)) == Set(identifiers))
    }

    /// Выключенное правило без данных **в окне** — строки нет, даже когда запись у него в
    /// свёртке есть, но лежит за краем окна. Строку даёт запись **в окне**, а не наличие данных
    /// в истории: иначе правило, выключенное неделю назад, навсегда оставляло бы строку из семи
    /// прочерков — обычный путь, а не редкость. Выключенное правило **с** данными в окне —
    /// строка есть: строку даёт запись, а не включённость.
    @Test func rowsExcludeDisabledRuleWithoutData() throws {
        var rollup = FocusRollup()
        rollup.add(.seconds(300), to: telegram, on: day(2026, 9, 15))
        // Окно 09-11 … 09-17: у выключенного Safari запись есть, но на 09-04, вне окна.
        rollup.add(.seconds(300), to: safari, on: day(2026, 9, 4))

        let config = try rules([safari, telegram], enabled: false)
        let summary = FocusSummary(rollup: rollup, config: config, now: septemberSeventeenth)

        #expect(!summary.days.contains(day(2026, 9, 4)))
        #expect(summary.rows.map(\.bundleIdentifier) == [telegram])
        #expect(!summary.rows.contains { $0.bundleIdentifier == safari })
    }

    /// Данные только за первый день перед окном и раньше, правила нет — строки нет, и ни одна
    /// ячейка ни одной строки этот день не отражает.
    @Test func rowsExcludeDataOutsideWindow() throws {
        // Окно 09-11 … 09-17. 09-10 — первый день перед окном, 09-01 — глубже.
        var rollup = FocusRollup()
        rollup.add(.seconds(900), to: finder, on: day(2026, 9, 10))
        rollup.add(.seconds(700), to: finder, on: day(2026, 9, 1))
        rollup.add(.seconds(500), to: telegram, on: day(2026, 9, 10))
        rollup.add(.seconds(120), to: telegram, on: day(2026, 9, 13))

        let summary = FocusSummary(rollup: rollup, config: .empty, now: septemberSeventeenth)

        #expect(!summary.days.contains(day(2026, 9, 10)))
        #expect(summary.rows.map(\.bundleIdentifier) == [telegram])
        let row = try #require(summary.rows.first)
        #expect(row.total == .seconds(120))
        #expect(row.perDay == [nil, nil, .seconds(120), nil, nil, nil, nil])
        #expect(summary.recordedDayCount == 1)
    }

    /// Нижняя граница окна для набора строк: единственная запись приложения лежит в самом
    /// старом дне окна, правила нет — строка есть.
    @Test func rowsIncludeDataOnOldestWindowDay() throws {
        var rollup = FocusRollup()
        rollup.add(.seconds(420), to: finder, on: day(2026, 9, 11))

        let summary = FocusSummary(rollup: rollup, config: .empty, now: septemberSeventeenth)

        #expect(summary.days[0] == day(2026, 9, 11))
        let row = try #require(summary.rows.first { $0.bundleIdentifier == finder })
        #expect(row.perDay[0] == .seconds(420))
        #expect(row.total == .seconds(420))
        #expect(summary.rows.map(\.bundleIdentifier) == [finder])
    }

    /// Идентификаторы сопоставляются **точным равенством ключа**, а не префиксом и не без учёта
    /// регистра. `hasPrefix` — ловушка, названная в `Rule.swift` по имени: он затянул бы в строку
    /// основного приложения его же хелперы (findings §10), приписав ему чужие секунды.
    /// Регистронезависимый поиск склеил бы два разных идентификатора в один.
    ///
    /// Три похожих идентификатора здесь — три разных приложения: данные ни одного из них не
    /// перетекают в строку соседа, а у правила без своих данных итог остаётся нулевым.
    @Test func identifiersMatchExactlyNotByPrefixOrCase() throws {
        let safariHelper = "com.apple.SafariHelper"
        let safariUpperCased = "com.apple.SAFARI"

        var rollup = FocusRollup()
        rollup.add(.seconds(600), to: safariHelper, on: day(2026, 9, 14))
        rollup.add(.seconds(300), to: safariUpperCased, on: day(2026, 9, 14))

        let config = try rules([safari], enabled: true)
        let summary = FocusSummary(rollup: rollup, config: config, now: septemberSeventeenth)

        #expect(summary.days[3] == day(2026, 9, 14))

        // День записан, а записи у `com.apple.Safari` в нём нет: ноль, а не чужие секунды.
        let exact = try #require(summary.rows.first { $0.bundleIdentifier == safari })
        #expect(exact.total == .zero)
        #expect(exact.perDay[3] == .zero)
        #expect(FocusSummary.cellText(exact.perDay[3]) == "0")

        let helperRow = try #require(summary.rows.first { $0.bundleIdentifier == safariHelper })
        #expect(helperRow.total == .seconds(600))
        #expect(helperRow.perDay[3] == .seconds(600))

        let upperCasedRow = try #require(
            summary.rows.first { $0.bundleIdentifier == safariUpperCased }
        )
        #expect(upperCasedRow.total == .seconds(300))
        #expect(upperCasedRow.perDay[3] == .seconds(300))

        #expect(summary.rows.count == 3)
        #expect(summary.rows.map(\.bundleIdentifier) == [safariHelper, safariUpperCased, safari])
    }

    /// Строку даёт наличие записи, а не её величина: запись со значением `.zero` — строка есть.
    /// С диска такой снимок не приходит (`add` роняет ноль), но определение — «есть запись».
    @Test func zeroValuedEntryStillProducesARow() throws {
        let rollup = FocusRollup(days: [day(2026, 9, 14): [finder: .zero]])

        let summary = FocusSummary(rollup: rollup, config: .empty, now: septemberSeventeenth)

        let row = try #require(summary.rows.first { $0.bundleIdentifier == finder })
        #expect(row.total == .zero)
        #expect(row.perDay[3] == .zero)
    }

    // MARK: - Порядок

    /// Критерий 8. Итог по убыванию, ничья — по `bundleIdentifier` по возрастанию, обычным
    /// сравнением строк.
    ///
    /// Порядок подачи здесь ничего не доказывает: входы — словари (`RuleConfig.rules`,
    /// `FocusRollup.days`), строки собираются через `Set`, а порядок их обхода зависит от
    /// хеш-сида процесса и до сортировки не доходит. Поэтому тай-брейк фиксируется иначе:
    ///
    /// - в ничьей **шесть** участников — без тай-брейка верный порядок выпадает случайно с
    ///   вероятностью 1/720, а не в каждом втором прогоне, как при двух;
    /// - id подобраны так, что способы сравнения расходятся: обычное сравнение ставит
    ///   заглавные раньше строчных, а регистронезависимое и локализованное дают
    ///   `finder, printcenter, Safari, TextEdit, Fork, Telegram`.
    @Test func orderIsTotalDescendingThenBundleIdentifier() throws {
        var rollup = FocusRollup()
        // Ничья по 600 с; у части участников итог разложен по разным дням.
        rollup.add(.seconds(600), to: fork, on: day(2026, 9, 12))
        rollup.add(.seconds(200), to: safari, on: day(2026, 9, 11))
        rollup.add(.seconds(400), to: safari, on: day(2026, 9, 15))
        rollup.add(.seconds(600), to: textEdit, on: day(2026, 9, 17))
        rollup.add(.seconds(300), to: finder, on: day(2026, 9, 13))
        rollup.add(.seconds(300), to: finder, on: day(2026, 9, 16))
        rollup.add(.seconds(100), to: printCenter, on: day(2026, 9, 12))
        rollup.add(.seconds(500), to: printCenter, on: day(2026, 9, 14))
        rollup.add(.seconds(600), to: telegram, on: day(2026, 9, 14))
        // Больше всех.
        rollup.add(.seconds(3600), to: xcode, on: day(2026, 9, 16))
        // Меньше ничьей, но не ноль.
        rollup.add(.seconds(11), to: terminal, on: day(2026, 9, 14))

        // Включённое правило без данных — итог ноль, строка последней.
        let config = try rules([telegram, safari, fork, notes], enabled: true)
        let summary = FocusSummary(rollup: rollup, config: config, now: septemberSeventeenth)

        #expect(summary.rows.map(\.bundleIdentifier) == [
            "com.apple.dt.Xcode",
            "com.DanPristupov.Fork", "com.apple.Safari", "com.apple.TextEdit", "com.apple.finder",
            "com.apple.printcenter", "ru.keepcoder.Telegram",
            "com.apple.Terminal",
            "com.apple.Notes",
        ])
        #expect(summary.rows.map(\.total) == [
            .seconds(3600),
            .seconds(600), .seconds(600), .seconds(600), .seconds(600), .seconds(600), .seconds(600),
            .seconds(11),
            .zero,
        ])
    }

    /// Первичный ключ — точный `total`, а не целые секунды: итоги, различающиеся долями
    /// секунды, ничьей не являются.
    ///
    /// Участники подобраны так, что округление до целых секунд меняет ответ: у алфавитно
    /// меньшего `com.apple.Safari` итог **меньше**, поэтому по точным итогам первым идёт
    /// Telegram, а по округлённым это ничья и алфавитный тай-брейк ставит первым Safari.
    /// Субсекундные итоги в снимке реальны: TASK-101 складывает записанное с ещё не
    /// сброшенным на диск.
    @Test func orderUsesExactTotalsNotWholeSeconds() throws {
        var rollup = FocusRollup()
        rollup.add(.seconds(600), to: safari, on: day(2026, 9, 14))
        rollup.add(.seconds(600), to: telegram, on: day(2026, 9, 14))
        rollup.add(.milliseconds(500), to: telegram, on: day(2026, 9, 16))

        let summary = FocusSummary(rollup: rollup, config: .empty, now: septemberSeventeenth)

        #expect(summary.rows.map(\.bundleIdentifier) == [telegram, safari])
        #expect(summary.rows.map(\.total) == [
            .seconds(600) + .milliseconds(500),
            .seconds(600),
        ])
    }

    /// Ничья на **нуле** — отдельный случай, и самый частый: на свежей неделе нулевыми будут
    /// все строки сразу. Без тай-брейка порядок всей таблицы достался бы порядку обхода `Set`,
    /// то есть хеш-сиду процесса. Четырёх участников достаточно: случайно верный порядок — 1/24.
    @Test func zeroTotalRowsAreOrderedByIdentifier() throws {
        let config = try rules([finder, safari, notes, fork], enabled: true)

        let summary = FocusSummary(rollup: .empty, config: config, now: septemberSeventeenth)

        #expect(summary.rows.map(\.total) == [.zero, .zero, .zero, .zero])
        #expect(summary.rows.map(\.bundleIdentifier) == [
            "com.DanPristupov.Fork", "com.apple.Notes", "com.apple.Safari", "com.apple.finder",
        ])
    }

    // MARK: - API

    /// Раздел «API» требует у обоих типов `Equatable` и `Sendable`, и снятие любого из двух
    /// остальными тестами не видно. Равенство — чтобы сравнивать сводки целиком; `Sendable`
    /// понадобится TASK-101 при передаче снимка.
    ///
    /// Равенство проверяется **по всем полям**, а не по тем, которыми входы различаются проще
    /// всего. Отдельно закреплены две пары: сводки с одинаковыми `days` и `recordedDayCount`,
    /// различающиеся только строками, и строки с одинаковыми идентификатором и итогом,
    /// различающиеся только ячейками. Иначе равенство, забывшее половину полей, прошло бы — и
    /// вместе с ним прошла бы проверка `awake` ниже, которая целиком на него опирается.
    ///
    /// Здесь же — единственное место, где различается `awake`. Из трёх полей `Now` сводке нужны
    /// `wall` и `timeZone`; шкала бодрствования к календарному дню отношения не имеет (findings
    /// §9), поэтому сводки, различающиеся **только** `awake`, равны целиком — и строками, и
    /// знаменателем. Во всех остальных тестах `awake` один и тот же, и чтение этого поля было бы
    /// в них неотличимо от верной реализации.
    @Test func summaryTypesConformToEquatableAndSendable() throws {
        var rollup = FocusRollup()
        rollup.add(.seconds(600), to: telegram, on: day(2026, 9, 14))
        rollup.add(.seconds(11), to: finder, on: day(2026, 9, 16))
        let config = try rules([safari], enabled: true)

        let summary = FocusSummary(rollup: rollup, config: config, now: septemberSeventeenth)
        let same = FocusSummary(rollup: rollup, config: config, now: septemberSeventeenth)
        #expect(summary == same)

        var otherRollup = rollup
        otherRollup.add(.seconds(60), to: telegram, on: day(2026, 9, 15))
        let other = FocusSummary(rollup: otherRollup, config: config, now: septemberSeventeenth)
        #expect(summary != other)

        let row = try #require(summary.rows.first { $0.bundleIdentifier == telegram })
        let sameRow = try #require(same.rows.first { $0.bundleIdentifier == telegram })
        let otherRow = try #require(other.rows.first { $0.bundleIdentifier == telegram })
        #expect(row == sameRow)
        #expect(row != otherRow)

        // `Sendable` проверяется компилятором: функция-свидетель требует конформанса от типа
        // аргумента, и без него этот файл не собирается. Ядро синхронное — ни `Task`, ни
        // `@Sendable`-замыканий здесь не заводится.
        requiresSendable(summary)
        requiresSendable(row)

        // Равенство сводки держится не на одном знаменателе: у этой пары совпадают и `days`, и
        // `recordedDayCount` — записан один и тот же день, — а различаются только строки.
        let oneApp = FocusSummary(
            rollup: FocusRollup(days: [day(2026, 9, 14): [telegram: .seconds(600)]]),
            config: .empty,
            now: septemberSeventeenth
        )
        let anotherApp = FocusSummary(
            rollup: FocusRollup(days: [day(2026, 9, 14): [safari: .seconds(600)]]),
            config: .empty,
            now: septemberSeventeenth
        )
        #expect(oneApp.days == anotherApp.days)
        #expect(oneApp.recordedDayCount == anotherApp.recordedDayCount)
        #expect(oneApp != anotherApp)

        // Равенство строки держится не на одном итоге: у этой пары совпадают идентификатор и
        // итог, а различаются ячейки — те же 600 с записаны в разные дни окна.
        let recordedEarlier = FocusSummary(
            rollup: FocusRollup(days: [day(2026, 9, 12): [telegram: .seconds(600)]]),
            config: .empty,
            now: septemberSeventeenth
        )
        let recordedLater = FocusSummary(
            rollup: FocusRollup(days: [day(2026, 9, 14): [telegram: .seconds(600)]]),
            config: .empty,
            now: septemberSeventeenth
        )
        let earlierRow = try #require(recordedEarlier.rows.first)
        let laterRow = try #require(recordedLater.rows.first)
        #expect(earlierRow.bundleIdentifier == laterRow.bundleIdentifier)
        #expect(earlierRow.total == laterRow.total)
        #expect(earlierRow.perDay != laterRow.perDay)
        #expect(earlierRow != laterRow)

        // Тот же `wall` и тот же пояс, другая шкала бодрствования — сводка та же.
        let awakeLonger = FocusSummary(
            rollup: rollup,
            config: config,
            now: moment(utc, 2026, 9, 17, 14, 0, awake: .seconds(151_200))
        )
        #expect(summary.recordedDayCount == 2)
        #expect(awakeLonger == summary)
    }

    // MARK: - Знаменатель

    /// Критерий 10. Знаменатель считает только записанные дни окна: ключи **до** и **после**
    /// окна не в счёт, ключ с пустым словарём приложений — в счёт. Полностью записанная неделя
    /// даёт `7 of 7 days recorded`.
    ///
    /// Последний сценарий — окно через границу месяца: там «день окна» и «день между краями
    /// окна» перестают совпадать, и знаменатель обязан считать первое.
    @Test func denominatorCountsRecordedDaysOnly() {
        // Окно 09-11 … 09-17. Записаны шесть дней окна, включая крайние, и два дня за его
        // краями: 09-10 перед окном и 09-18 после. Ключ после окна достижим при переводе часов
        // назад или смене пояса после слива, и его приложение строки давать не должно.
        var rollup = FocusRollup()
        for recordedDay in [11, 12, 13, 15, 16, 17] {
            rollup.add(.seconds(60), to: telegram, on: day(2026, 9, recordedDay))
        }
        rollup.add(.seconds(60), to: telegram, on: day(2026, 9, 10))
        rollup.add(.seconds(60), to: finder, on: day(2026, 9, 18))

        let six = FocusSummary(rollup: rollup, config: .empty, now: septemberSeventeenth)
        #expect(six.recordedDayCount == 6)
        #expect(six.recordedDaysText == "6 of 7 days recorded")
        #expect(six.rows.map(\.bundleIdentifier) == [telegram])

        // Семь из семи — состояние, к которому идёт собираемая сейчас неделя.
        var everyDay = FocusRollup()
        for recordedDay in 11...17 {
            everyDay.add(.seconds(60), to: telegram, on: day(2026, 9, recordedDay))
        }
        let full = FocusSummary(rollup: everyDay, config: .empty, now: septemberSeventeenth)
        #expect(full.recordedDayCount == 7)
        #expect(full.recordedDaysText == "7 of 7 days recorded")

        let none = FocusSummary(rollup: .empty, config: .empty, now: septemberSeventeenth)
        #expect(none.recordedDayCount == 0)
        #expect(none.recordedDaysText == "0 of 7 days recorded")

        let emptyKey = FocusRollup(days: [day(2026, 9, 14): [:]])
        let one = FocusSummary(rollup: emptyKey, config: .empty, now: septemberSeventeenth)
        #expect(one.recordedDayCount == 1)
        #expect(one.recordedDaysText == "1 of 7 days recorded")
        #expect(one.rows.isEmpty)

        // Окно через границу месяца: 06-26 … 07-02. Ключ `2026-06-31` формат допускает (день в
        // `1...31`), и правка `focus.json` руками его создаёт, хотя такого дня в июне нет. Днём
        // окна он не является — но лежит **между** первым и последним его днём по `Comparable`.
        // Знаменатель считает принадлежность окну, а не попадание в диапазон между его краями.
        let outOfCalendarDay = day(2026, 6, 31)
        let acrossMonths = FocusSummary(
            rollup: FocusRollup(days: [outOfCalendarDay: [telegram: .seconds(600)]]),
            config: .empty,
            now: moment(utc, 2026, 7, 2, 14, 0)
        )
        #expect(acrossMonths.days == [
            day(2026, 6, 26), day(2026, 6, 27), day(2026, 6, 28), day(2026, 6, 29),
            day(2026, 6, 30), day(2026, 7, 1), day(2026, 7, 2),
        ])
        #expect(!acrossMonths.days.contains(outOfCalendarDay))
        #expect(acrossMonths.days[0] < outOfCalendarDay)
        #expect(outOfCalendarDay < acrossMonths.days[6])
        #expect(acrossMonths.recordedDayCount == 0)
        #expect(acrossMonths.recordedDaysText == "0 of 7 days recorded")
        #expect(acrossMonths.rows.isEmpty)
    }

    // MARK: - Насыщение

    /// TASK-101. Итог от `Int64.max` секунд и выше насыщается вместо падения: иначе
    /// `Duration.components` переполняется, а декодер принимает любую неотрицательную `Int` на
    /// день, так что двух исправленных руками дней ≥ 2⁶² в окне достаточно. Падение убило бы
    /// резидента, которого никто не перезапустит (DEC-006).
    ///
    /// Граница точна с обеих сторон: ровно `Int64.max` секунд — уже насыщение, на
    /// наносекунду и на секунду меньше — ещё обычный путь. Первый символ — U+2265, пробела после
    /// него нет, как у `<1 s`.
    @Test func totalSaturatesInsteadOfTrapping() {
        #expect(FocusSummary.totalText(.seconds(Int64.max) + .seconds(Int64.max)) == "≥2562047788015215 h")
        #expect(FocusSummary.totalText(.seconds(Int64.max)) == "≥2562047788015215 h")
        #expect(FocusSummary.totalText(.seconds(Int64.max)).unicodeScalars.first?.value == 0x2265)

        #expect(FocusSummary.totalText(.seconds(Int64.max) - .nanoseconds(1)) == "2562047788015215 h 30 m")
        #expect(FocusSummary.totalText(.seconds(Int64.max - 1)) == "2562047788015215 h 30 m")
    }

    /// TASK-101. Ячейка насыщается на той же границе, что и итог, и по той же причине.
    @Test func cellSaturatesInsteadOfTrapping() {
        #expect(FocusSummary.cellText(.seconds(Int64.max) + .seconds(Int64.max)) == "≥153722867280912930")
        #expect(FocusSummary.cellText(.seconds(Int64.max)) == "≥153722867280912930")
        #expect(FocusSummary.cellText(.seconds(Int64.max)).unicodeScalars.first?.value == 0x2265)

        #expect(FocusSummary.cellText(.seconds(Int64.max) - .nanoseconds(1)) == "153722867280912930")
        #expect(FocusSummary.cellText(.seconds(Int64.max - 1)) == "153722867280912930")
    }
}

// MARK: - Хелперы

private let telegram = "ru.keepcoder.Telegram"
private let safari = "com.apple.Safari"
private let finder = "com.apple.finder"
private let xcode = "com.apple.dt.Xcode"
private let notes = "com.apple.Notes"
private let fork = "com.DanPristupov.Fork"
private let textEdit = "com.apple.TextEdit"
private let printCenter = "com.apple.printcenter"
private let terminal = "com.apple.Terminal"

private let utc = TimeZone(secondsFromGMT: 0)!

/// Сегодня для большинства сценариев: 17 сентября 2026, 14:00 UTC. Окно — 09-11 … 09-17.
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

/// `Now` из явных частей. Шкала бодрствования сводке не нужна — момент на ней произвольный, и по
/// умолчанию он нулевой; задаётся он только там, где проверяется, что сводка `awake` не читает.
private func moment(
    _ zone: TimeZone,
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int = 0,
    _ minute: Int = 0,
    awake: Duration = .zero
) -> Now {
    Now(
        wall: instant(zone, year, month, day, hour, minute),
        awake: AwakeInstant(sinceOrigin: awake),
        timeZone: zone
    )
}

/// Свидетель конформанса `Sendable`: вызов не компилируется, если у типа аргумента его нет.
/// Тело пустое намеренно — проверка целиком на этапе компиляции.
private func requiresSendable<T: Sendable>(_ value: T) {}

/// Конфиг из правил с одинаковым состоянием включённости и лимитом 10 минут.
private func rules(_ identifiers: [String], enabled: Bool) throws -> RuleConfig {
    let enabledAt: Date? = enabled ? instant(utc, 2026, 9, 1, 9, 0) : nil
    return RuleConfig(try identifiers.map {
        try Rule(bundleIdentifier: $0, limit: .constant(.seconds(600)), enabledAt: enabledAt)
    })
}
