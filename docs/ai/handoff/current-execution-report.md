# Отчёт об исполнении — раунд 6

## Задача

TASK-108 — Focus summary: core computation. Раунд 6 (последний содержательный),
пакет `docs/ai/handoff/current-task-packet.md`.

## Кратко

Внесены T19–T24 — **только в тестовый файл**. Исходник `FocusSummary.swift` не менялся:
хеш до и после совпал (`be36acfc68ef…13388877`), `git diff --no-index` против копии пуст.
Сьют — 25 тестов (T19 вынесен отдельным тестом `enabledRuleIgnoresDataOutsideTheWindow`),
один сьют, зелёный. Все шесть мутантов M30–M35 убиты названными в пакете тестами, файл после
каждого восстановлен копированием.

Запрещённое не выполнялось: безфильтрового `swift test` не было, `./build.sh` не запускался,
приложение не запускалось, `~/Library/Application Support/com.svvoff.terminator/` не трогался,
git — только `status`/`diff`/`diff --no-index`.

## Изменённые файлы

| Файл | Что изменено |
|---|---|
| `Tests/TerminatorCoreTests/FocusSummaryTests.swift` | T19 — новый тест `enabledRuleIgnoresDataOutsideTheWindow`; T20 и T21 — две пары в `summaryTypesConformToEquatableAndSendable` плюс расширенный док-комментарий; T22 — одно утверждение в `enabledRulesSurviveAnEmptyWindow`; T23 — окно через границу месяца в `denominatorCountsRecordedDaysOnly` плюс две строки док-комментария; T24 — две точки в `totalTextCoversEveryUnit` |
| `Sources/TerminatorCore/FocusSummary.swift` | **не менялся** (мутации M30–M35 временные, откачены копированием; хеш совпал) |
| `docs/ai/handoff/current-execution-report.md` | этот отчёт |

## Изменения поведения

Продакшн-кода в раунде нет: поведение `FocusSummary` не изменилось ни на символ. Изменилась
только сила тестов.

### Раунд 6: T19–T24 — что сделано по каждому пункту

**T19 (minor). Итог включённого правила, у которого данные есть только вне окна.**
Заведён отдельный тест `enabledRuleIgnoresDataOutsideTheWindow` (выбор отдельного теста, а не
дополнения `rowsIncludeEnabledRuleWithNoData`, — поэтому в сьюте 25 тестов, а не 24: у случая своя
посылка — данные есть, но окно их не видит, — и в док-комментарии она названа отдельно).
Вход ровно из пакета: Safari **включён**, единственная запись — 300 с на 09-04 при `now` = 09-17.
Утверждается: 09-04 в окно не входит, строка одна и она Safari, `perDay` — семь `nil`,
`total == .zero`, `totalText == "0 s"`, `recordedDayCount == 0`.
Доказательство силы — M30: без исправления реализация показывает `5 m`, ровно как предсказал пакет.

**T20 (minor). Равенство сводки держится не на строках.**
В `summaryTypesConformToEquatableAndSendable` добавлена пара, различающаяся **только строками**:
`{09-14: [telegram: 600]}` против `{09-14: [safari: 600]}`. Отдельными утверждениями закреплено,
что `days` и `recordedDayCount` у них совпадают, — иначе пара не отличалась бы от прежней. Убивает
M31.

**T21 (minor). Равенство строки держится не на ячейках.**
Там же — пара строк с одинаковым идентификатором и одинаковым итогом, но разными днями: 600 с на
09-12 против 600 с на 09-14. Закреплено, что `bundleIdentifier` и `total` равны, а `perDay` — нет.
Убивает M32.

**T22 (nit). Равенство строки без `bundleIdentifier`.**
В `enabledRulesSurviveAnEmptyWindow` добавлено `#expect(summary.rows[0] != summary.rows[1])`: две
строки пустой недели совпадают до символа во всём, кроме идентификатора. Убивает M33.

**T23 (nit). Знаменатель как лексикографический диапазон вместо принадлежности окну.**
В `denominatorCountsRecordedDaysOnly` добавлен сценарий с окном через границу месяца: `now` =
2026-07-02 (окно 06-26 … 07-02), в свёртке ключ `DayKey(year: 2026, month: 6, day: 31)`. Утверждается
и сам разрыв: ключ **не** день окна, но `days[0] < 06-31 < days[6]` по `Comparable`. Ожидания —
`recordedDayCount == 0`, `"0 of 7 days recorded"`, `rows.isEmpty`. Убивает M34.

**T24 (nit). Верхний край таблицы итогов.**
В `totalTextCoversEveryUnit` добавлены `.seconds(360_000)` → `"100 h 0 m"` и `.seconds(604_740)` →
`"167 h 59 m"`. Убивает M35.

**Ожидания не подгонялись.** Все шесть добавленных ожиданий прошли на неизменённой реализации с
первого прогона; ни одно не переписывалось под полученный результат.

## Доказательства валидации

| Команда | Результат | Вывод |
|---|---|---|
| `shasum -a 256 Sources/TerminatorCore/FocusSummary.swift` (до правок) | `be36acfc68ef…13388877` | совпал с пакетом |
| `swift test --filter FocusSummaryTests` | EXIT=0 | 25 тестов, один сьют «Сводка фокуса» |
| M30 | EXIT=1, упал `enabledRuleIgnoresDataOutsideTheWindow` | ниже |
| M31 | EXIT=1, упал `summaryTypesConformToEquatableAndSendable` | ниже |
| M32 | EXIT=1, упал `summaryTypesConformToEquatableAndSendable` | ниже |
| M33 | EXIT=1, упали `enabledRulesSurviveAnEmptyWindow` и `summaryTypesConformToEquatableAndSendable` | ниже |
| M34 | EXIT=1, упал `denominatorCountsRecordedDaysOnly` | ниже |
| M35 | EXIT=1, упал `totalTextCoversEveryUnit` | ниже |
| `shasum -a 256` после всех восстановлений | `be36acfc68ef…13388877` | совпал |
| `git diff --no-index "$TMPDIR/FocusSummary.r5.swift" Sources/…/FocusSummary.swift` | `diff rc=0` | дифф пуст |
| `swift test --filter FocusSummaryTests` (финальный) | EXIT=0 | 25/25 |
| `swift build` | EXIT=0 | `grep -c 'warning:'` → **0** |
| `swift build -c release` | EXIT=0 | `grep -c 'warning:'` → **0** |
| `scripts/check-forbidden.sh` | EXIT=0 | `OK: запрещённых конструкций не найдено` |
| грепы 1 и 2 | `rc=1` (пусто) | ниже |

### 1. Хеш исходника до правок и копия

```
be36acfc68ef8cde3de730c9733f72763279554c2dc2f4d0a60fb9aa13388877  $TMPDIR/FocusSummary.r5.swift
0a273e1fbb2dfea854ccd1e729d33f4b0942f1e3abe2981c6c1256ff80a39b66  $TMPDIR/FocusSummaryTests.r5.swift
```

### 2. Фильтрованный прогон после правок (полный вывод тестовой части)

```
EXIT=0
Building for debugging...
[4/8] Compiling TerminatorCore FocusSummary.swift
[7/8] Compiling TerminatorCoreTests FocusSummaryTests.swift
Build complete! (3.18s)
◇ Test run started.
↳ Testing Library Version: 1902
↳ Target Platform: arm64e-apple-macos14.0
◇ Suite "Сводка фокуса" started.
◇ Test summaryTypesConformToEquatableAndSendable() started.
◇ Test windowCrossesDaylightSavingCorrectly() started.
◇ Test orderIsTotalDescendingThenBundleIdentifier() started.
◇ Test identifiersMatchExactlyNotByPrefixOrCase() started.
◇ Test orderUsesExactTotalsNotWholeSeconds() started.
◇ Test enabledRulesSurviveAnEmptyWindow() started.
◇ Test zeroValuedEntryStillProducesARow() started.
◇ Test subSecondTotalIsNotZero() started.
◇ Test emptyDayKeyShowsZeroInCells() started.
◇ Test cellsTruncateDownNeverUp() started.
◇ Test windowIsSevenDaysEndingToday() started.
◇ Test zeroTotalRowsAreOrderedByIdentifier() started.
◇ Test rowsExcludeDisabledRuleWithoutData() started.
◇ Test rowSetIsNotTruncated() started.
◇ Test enabledRuleIgnoresDataOutsideTheWindow() started.
◇ Test denominatorCountsRecordedDaysOnly() started.
◇ Test subMinuteRendersAsLessThanOne() started.
◇ Test rowsExcludeDataOutsideWindow() started.
◇ Test missingDayIsNilNotZero() started.
◇ Test totalTextCoversEveryUnit() started.
◇ Test rowsIncludeDataOnOldestWindowDay() started.
◇ Test subMillisecondRemainderSurvivesSummation() started.
◇ Test rowsIncludeEnabledRuleWithNoData() started.
◇ Test recordedDayWithoutAppIsZero() started.
◇ Test rowsIncludeHistoryWithoutARule() started.
✔ Test emptyDayKeyShowsZeroInCells() passed after 0.001 seconds.
✔ Test subSecondTotalIsNotZero() passed after 0.001 seconds.
✔ Test windowIsSevenDaysEndingToday() passed after 0.001 seconds.
✔ Test cellsTruncateDownNeverUp() passed after 0.001 seconds.
✔ Test rowsExcludeDisabledRuleWithoutData() passed after 0.001 seconds.
✔ Test zeroTotalRowsAreOrderedByIdentifier() passed after 0.001 seconds.
✔ Test windowCrossesDaylightSavingCorrectly() passed after 0.001 seconds.
✔ Test zeroValuedEntryStillProducesARow() passed after 0.001 seconds.
✔ Test orderIsTotalDescendingThenBundleIdentifier() passed after 0.001 seconds.
✔ Test orderUsesExactTotalsNotWholeSeconds() passed after 0.001 seconds.
✔ Test enabledRulesSurviveAnEmptyWindow() passed after 0.001 seconds.
✔ Test enabledRuleIgnoresDataOutsideTheWindow() passed after 0.001 seconds.
✔ Test rowsExcludeDataOutsideWindow() passed after 0.001 seconds.
✔ Test totalTextCoversEveryUnit() passed after 0.001 seconds.
✔ Test identifiersMatchExactlyNotByPrefixOrCase() passed after 0.001 seconds.
✔ Test recordedDayWithoutAppIsZero() passed after 0.001 seconds.
✔ Test rowsIncludeDataOnOldestWindowDay() passed after 0.001 seconds.
✔ Test denominatorCountsRecordedDaysOnly() passed after 0.001 seconds.
✔ Test summaryTypesConformToEquatableAndSendable() passed after 0.001 seconds.
✔ Test rowSetIsNotTruncated() passed after 0.001 seconds.
✔ Test subMinuteRendersAsLessThanOne() passed after 0.001 seconds.
✔ Test subMillisecondRemainderSurvivesSummation() passed after 0.001 seconds.
✔ Test missingDayIsNilNotZero() passed after 0.001 seconds.
✔ Test rowsIncludeHistoryWithoutARule() passed after 0.001 seconds.
✔ Test rowsIncludeEnabledRuleWithNoData() passed after 0.001 seconds.
✔ Suite "Сводка фокуса" passed after 0.001 seconds.
✔ Test run with 25 tests in 1 suite passed after 0.001 seconds.
```

Один сьют, посторонних сьютов в выводе нет. Строка `Executed 0 tests` выше относится к пустому
XCTest-набору (весь сьют — swift-testing) и появляется в каждом прогоне этой задачи.

### 3. Мутации M30–M35

Схема каждой: правка рабочего файла исходника → `swift test --filter FocusSummaryTests` →
дословные строки провала → `cp "$TMPDIR/FocusSummary.r5.swift" Sources/TerminatorCore/FocusSummary.swift`
→ `shasum` совпал. Восстановление — **копированием**, git не использовался.

#### M30 — при нулевой сумме по окну брать сумму по всей свёртке

Было:

```swift
let total = perDay.reduce(Duration.zero) { sum, cell in sum + (cell ?? .zero) }
```

Стало:

```swift
var total = perDay.reduce(Duration.zero) { sum, cell in sum + (cell ?? .zero) }
if total == .zero {
    total = rollup.days.values.reduce(Duration.zero) { sum, apps in
        sum + (apps[bundleIdentifier] ?? .zero)
    }
}
```

Упал ровно названный тест:

```
✘ Test enabledRuleIgnoresDataOutsideTheWindow() recorded an issue at FocusSummaryTests.swift:352:9: Expectation failed: (row.total → 300.0 seconds) == (.zero → 0.0 seconds)
✘ Test enabledRuleIgnoresDataOutsideTheWindow() recorded an issue at FocusSummaryTests.swift:353:9: Expectation failed: (FocusSummary.totalText(row.total) → "5 m") == "0 s"
✘ Test enabledRuleIgnoresDataOutsideTheWindow() failed after 0.001 seconds with 2 issues.
✘ Test run with 25 tests in 1 suite failed after 0.001 seconds with 2 issues.
```

Других упавших тестов нет. Видимое неверное число — `5 m` — совпало с предсказанием пакета.
Хеш после восстановления: `be36acfc68ef8cde3de730c9733f72763279554c2dc2f4d0a60fb9aa13388877`.

#### M31 — `FocusSummary.==` сравнивает только `days` и `recordedDayCount`

Добавлено в `FocusSummary` (синтезированное равенство подавляется рукописным):

```swift
public static func == (lhs: FocusSummary, rhs: FocusSummary) -> Bool {
    lhs.days == rhs.days && lhs.recordedDayCount == rhs.recordedDayCount
}
```

```
✘ Test summaryTypesConformToEquatableAndSendable() recorded an issue at FocusSummaryTests.swift:653:9: Expectation failed: (oneApp → FocusSummary(days: [2026-09-11, …, 2026-09-17], recordedDayCount: 1, rows: [TerminatorCore.FocusSummaryRow(bundleIdentifier: "ru.keepcoder.Telegram", total: 600.0 seconds, perDay: [nil, nil, nil, Optional(600.0 seconds), nil, nil, nil])])) != (anotherApp → FocusSummary(days: [2026-09-11, …, 2026-09-17], recordedDayCount: 1, rows: [TerminatorCore.FocusSummaryRow(bundleIdentifier: "com.apple.Safari", total: 600.0 seconds, perDay: [nil, nil, nil, Optional(600.0 seconds), nil, nil, nil])]))
✘ Test summaryTypesConformToEquatableAndSendable() failed after 0.002 seconds with 1 issue.
✘ Test run with 25 tests in 1 suite failed after 0.002 seconds with 1 issue.
```

Упала именно новая пара T20; прежняя пара раунда 4 (`summary != other`) мутанта, как и
предсказывал ревьюер, не ловит. Хеш после восстановления совпал.

#### M32 — `FocusSummaryRow.==` без `perDay`

```swift
public static func == (lhs: FocusSummaryRow, rhs: FocusSummaryRow) -> Bool {
    lhs.bundleIdentifier == rhs.bundleIdentifier && lhs.total == rhs.total
}
```

```
✘ Test summaryTypesConformToEquatableAndSendable() recorded an issue at FocusSummaryTests.swift:672:9: Expectation failed: (earlierRow → FocusSummaryRow(bundleIdentifier: "ru.keepcoder.Telegram", total: 600.0 seconds, perDay: [nil, Optional(600.0 seconds), nil, nil, nil, nil, nil])) != (laterRow → FocusSummaryRow(bundleIdentifier: "ru.keepcoder.Telegram", total: 600.0 seconds, perDay: [nil, nil, nil, Optional(600.0 seconds), nil, nil, nil]))
✘ Test summaryTypesConformToEquatableAndSendable() failed after 0.001 seconds with 1 issue.
✘ Test run with 25 tests in 1 suite failed after 0.002 seconds with 1 issue.
```

Упала пара T21. Хеш после восстановления совпал.

#### M33 — `FocusSummaryRow.==` без `bundleIdentifier`

```swift
public static func == (lhs: FocusSummaryRow, rhs: FocusSummaryRow) -> Bool {
    lhs.total == rhs.total && lhs.perDay == rhs.perDay
}
```

```
✘ Test enabledRulesSurviveAnEmptyWindow() recorded an issue at FocusSummaryTests.swift:384:9: Expectation failed: (summary.rows[0] → FocusSummaryRow(bundleIdentifier: "com.apple.Safari", total: 0.0 seconds, perDay: [nil, nil, nil, nil, nil, nil, nil])) != (summary.rows[1] → FocusSummaryRow(bundleIdentifier: "ru.keepcoder.Telegram", total: 0.0 seconds, perDay: [nil, nil, nil, nil, nil, nil, nil]))
✘ Test enabledRulesSurviveAnEmptyWindow() failed after 0.001 seconds with 1 issue.
✘ Test summaryTypesConformToEquatableAndSendable() recorded an issue at FocusSummaryTests.swift:653:9: Expectation failed: (oneApp → …rows: [… "ru.keepcoder.Telegram" …]) != (anotherApp → …rows: [… "com.apple.Safari" …])
✘ Test run with 25 tests in 1 suite failed after 0.002 seconds with 2 issues.
```

Названный пакетом тест упал; вторым его поймала пара T20 — там строки тоже различаются только
идентификатором. Хеш после восстановления совпал.

#### M34 — знаменатель как диапазон `days[0] ... days[6]` по `Comparable`

Было:

```swift
self.recordedDayCount = recorded.filter { $0 != nil }.count
```

Стало:

```swift
self.recordedDayCount = rollup.days.keys.filter {
    $0 >= days[0] && $0 <= days[Self.dayCount - 1]
}.count
```

```
✘ Test denominatorCountsRecordedDaysOnly() recorded an issue at FocusSummaryTests.swift:744:9: Expectation failed: (acrossMonths.recordedDayCount → 1) == 0
✘ Test denominatorCountsRecordedDaysOnly() recorded an issue at FocusSummaryTests.swift:745:9: Expectation failed: (acrossMonths.recordedDaysText → "1 of 7 days recorded") == "0 of 7 days recorded"
✘ Test denominatorCountsRecordedDaysOnly() failed after 0.001 seconds with 2 issues.
✘ Test run with 25 tests in 1 suite failed after 0.001 seconds with 2 issues.
```

Упал только сценарий через границу месяца — все сентябрьские сценарии этого теста мутанта, как и
предсказано, не различают. Хеш после восстановления совпал.

#### M35 — `totalText` переключается на дни после 100 ч

```swift
if seconds >= 360_000 {
    return "\(seconds / 3600 / 24) d \(seconds / 3600 % 24) h"
}
return "\(seconds / 3600) h \(seconds % 3600 / 60) m"
```

```
✘ Test totalTextCoversEveryUnit() recorded an issue at FocusSummaryTests.swift:270:9: Expectation failed: (FocusSummary.totalText(.seconds(360_000)) → "4 d 4 h") == "100 h 0 m"
✘ Test totalTextCoversEveryUnit() recorded an issue at FocusSummaryTests.swift:271:9: Expectation failed: (FocusSummary.totalText(.seconds(604_740)) → "6 d 23 h") == "167 h 59 m"
✘ Test totalTextCoversEveryUnit() failed after 0.001 seconds with 2 issues.
✘ Test run with 25 tests in 1 suite failed after 0.001 seconds with 2 issues.
```

`4 d 4 h` — дословно то, что назвал пакет. Хеш после восстановления совпал.

### 4. Исходник не менялся

```
$ shasum -a 256 Sources/TerminatorCore/FocusSummary.swift
be36acfc68ef8cde3de730c9733f72763279554c2dc2f4d0a60fb9aa13388877  Sources/TerminatorCore/FocusSummary.swift
$ git diff --no-index "$TMPDIR/FocusSummary.r5.swift" Sources/TerminatorCore/FocusSummary.swift
diff rc=0 (0 = пусто)
```

Хеш тестового файла после правок: `6f4f148345fe6415fdd33ff8bf04fb0ef59f31a1ddf6f45b3bee46e8c7e31e2e`.

### 5. Финальный прогон после восстановления

```
EXIT=0
✔ Test missingDayIsNilNotZero() passed after 0.001 seconds.
✔ Test recordedDayWithoutAppIsZero() passed after 0.001 seconds.
✔ Test windowCrossesDaylightSavingCorrectly() passed after 0.001 seconds.
✔ Test summaryTypesConformToEquatableAndSendable() passed after 0.001 seconds.
✔ Suite "Сводка фокуса" passed after 0.002 seconds.
✔ Test run with 25 tests in 1 suite passed after 0.002 seconds.
```

### 6. Сборки (с `touch` перед каждой)

```
DEBUG EXIT=0
0
[3/6] Emitting module TerminatorCore
[4/6] Compiling TerminatorCore FocusSummary.swift
Build complete! (0.38s)

RELEASE EXIT=0
0
[1/3] Write swift-version--58304C5D6DBC2206.txt
[3/4] Compiling TerminatorCore AwakeInstant.swift
Build complete! (3.17s)
```

`grep -c 'warning:'` → `0` в обеих: **ноль** предупреждений и в debug, и в release.

### 7. Гейты и грепы

```
$ scripts/check-forbidden.sh
OK:    запрещённых конструкций не найдено
EXIT=0

$ grep -n -E 'focusStore\.load|Calendar\.current|TimeZone\.current|Date\(\)|86400|86_400|86 400|24 \* 60 \* 60|24 \* 3600|Bundle\.module|Logger|import AppKit|import SwiftUI|@testable' \
    Sources/TerminatorCore/FocusSummary.swift Tests/TerminatorCoreTests/FocusSummaryTests.swift
grep1 rc=1 (1 = пусто)

$ grep -n -i -E 'productiv|efficien|wasted|attention|trend|average|best|worst|streak|продуктивн|эффективн|впустую|внимани|тренд|средн|лучш|худш' \
    Sources/TerminatorCore/FocusSummary.swift Tests/TerminatorCoreTests/FocusSummaryTests.swift
grep2 rc=1 (1 = пусто)
```

## Acceptance criteria

| Критерий | Статус | Чем подтверждён |
|---|---|---|
| 1. Сьют только на Foundation + Testing + TerminatorCore, без sleep, ФС и реальных часов | выполнен | новый код раунда использует те же хелперы `moment`/`day`/`rules`; греп на `@testable`, `Date()`, `Calendar.current`, `TimeZone.current` пуст |
| 2. Тесты 1–13 с дословными именами | выполнен | прогон: все прежние имена на месте, T19–T24 их не переименовывали |
| 3. Мутация M1 | выполнен ранее (раунды 1–2) | в этом раунде не перепрогонялась: исходник побайтно тот же, что в раунде 5 |
| 4. Мутации M2, M3 | то же | то же |
| 5. `swift build` и `swift build -c release` зелёные, ноль `warning:` | выполнен | §6 |
| 6. `scripts/check-forbidden.sh` зелёный | выполнен | §7 |
| 7. Нет файлов под `Sources/Terminator/`; запрещённые конструкции отсутствуют | выполнен | §7 и `git status --short` ниже |
| 8. Запрещённые слова отсутствуют | выполнен | греп 2 пуст |
| 9. API в точности как в разделе «API» | выполнен | исходник не менялся, хеш совпал |
| 10. Строки форматирования в точности как в таблицах | выполнен | `totalTextCoversEveryUnit` (включая новые `100 h 0 m` и `167 h 59 m`), `cellsTruncateDownNeverUp` |
| 11. Безфильтровый `swift test`, `./build.sh`, запуск приложения **не выполнялись** | выполнен | все прогоны — только `swift test --filter FocusSummaryTests`; сборки — `swift build` в `.build/` |

Валидация раунда 6 по пакету:

| Пункт | Статус | Чем подтверждён |
|---|---|---|
| Хеш исходника до и после совпал, дифф пуст | выполнен | §1, §4 |
| Один сьют, 24 или 25 тестов | выполнен | **25** (T19 вынесен отдельным тестом — выбор назван в разделе T19) |
| Мутации M30–M35 с восстановлением | выполнен | §3, шесть мутантов мертвы, каждый уронил названный тест |
| Шаги 4–6 раунда 1 | выполнен | §5, §6, §7 |

## Не запускалось

- **Безфильтровый `swift test`** — запрещён пакетом: `ConfigStoreTests` пишет в ту же подсистему
  логов, откуда снимаются доказательства недели сбора. Заменён фильтрованным прогоном; остаточный
  риск — регрессия в других сьютах этой правкой невозможна: изменён только файл
  `FocusSummaryTests.swift`, на который никто не ссылается.
- **`./build.sh` и запуск приложения** — запрещены (findings §12, второй экземпляр затирает
  накопленные секунды). Заменены `swift build` и `swift build -c release`, которые пишут в
  `.build/` и резидента не трогают.
- **Мутанты M1–M29** прошлых раундов не перепрогонялись: исходник побайтно тот же, что в раунде 5
  (хеш `be36acfc68ef…13388877`), а тесты только добавлялись — ни один не ослаблен и не удалён.
- Пунктов `manual-checklist` в профиле карточки нет; человеку проверять нечего.

## Проверка скоупа

```
$ git status --short
 M docs/ai/current-context.md
 M docs/ai/handoff/current-execution-report.md
 M docs/ai/handoff/current-task-packet.md
RM docs/product/backlog/tasks/ready/TASK-108-focus-summary-core.md -> docs/product/backlog/tasks/in-progress/TASK-108-focus-summary-core.md
 M docs/product/decisions/active/DEC-005-focus-statistics.md
 M docs/product/decisions/active/DEC-006-anti-circumvention-non-goal.md
 M docs/product/decisions/index.md
?? Sources/TerminatorCore/FocusSummary.swift
?? Tests/TerminatorCoreTests/FocusSummaryTests.swift
```

Мои в этом раунде — только `Tests/TerminatorCoreTests/FocusSummaryTests.swift` и этот отчёт.
`Sources/TerminatorCore/FocusSummary.swift` числится новым файлом с прошлых раундов, но в раунде 6
не менялся (хеш совпал). Всё под `docs/`, кроме отчёта, — **правки оркестратора, не мои**:
`current-context.md`, `current-task-packet.md`, карточка TASK-108, DEC-005, DEC-006,
`decisions/index.md`. Не трогались и не откатывались.

Запрещённые зоны не тронуты: под `Sources/Terminator/` и `Sources/TerminatorAppKit/` изменений нет;
`FocusStore.swift`, `FocusFormat.swift`, `FocusLedger.swift`, `FocusRollup.swift` только читались;
`build.sh`, `Package.swift`, `scripts/`, `Packaging/` не менялись;
`~/Library/Application Support/com.svvoff.terminator/` не читался и не листался; git — только
`status`, `diff --stat`, `diff --no-index`; временные файлы — в `$TMPDIR`.

## Риски

- **Известное слепое пятно — «молчаливый топ-N»**: `rowSetIsNotTruncated` фиксирует двенадцать
  строк, и мутант `prefix(N)` с бо́льшим N его переживёт. Решение оркестратора: глубже не идти.
- Прежние слепые пятна и эквивалентные мутанты — как в раунде 5 (отсутствие публичного `init` у
  строки, идентификатор Terminator в данных, правило с пустым идентификатором, полдень как якорь,
  `preconditionFailure` → тихий возврат, `days.count` вместо `dayCount`, ключ словаря вместо
  `rule.bundleIdentifier`, `seconds / 60 % 60`, `components.seconds < 60`); «знаменатель из первой
  строки `perDay`» из этого списка выбыл — он убит.
- Остаточный риск `totalText` на итогах больше `Int64.max` секунд — как прежде, не чинится в этой
  карточке.
- Новый сценарий T23 использует ключ `2026-06-31`, которого в календаре нет. Он достижим только
  ручной правкой `focus.json` и в тесте служит ровно одному: отделить «день окна» от «день между
  краями окна». Продуктового поведения для несуществующих дат тест не объявляет — только то, что
  днём окна такой ключ не становится.

## Незавершённое и follow-up

- Продакшн-код в этом раунде не менялся — приёмка за оркестратором отдельным ходом (правило
  «не принимать собственную работу»).
- Follow-up для TASK-101 — прежние: предусловие «сводка строится один раз на открытие из
  замороженного снимка» лежит в док-комментарии `rows`; строки дней, разрешение имён приложений и
  пояснение «Terminator не работал» — там же, не здесь.
