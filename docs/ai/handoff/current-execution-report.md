# Отчёт об исполнении — TASK-101, фаза A

## Задача

TASK-101 — Statistics UI: секция «Focus» в поповере. **Только фаза A** (код + тесты, headless),
пакет `docs/ai/handoff/current-task-packet.md`, карточка
`docs/product/backlog/tasks/in-progress/TASK-101-statistics-ui.md`. Дата работы — 2026-09-18.

Статус: **DONE (фаза A)**. Статус карточки не трогался; фаза B (сборка бандла и ручной
чеклист) не моя и не начиналась.

## Кратко

- Ядро: новый `FocusSection` (три состояния: карантин → `unreadable`; иначе сводка
  `recorded.adding(accrued)`; ноль строк → `hidden`). В `FocusSummary.cellText/totalText`
  добавлено насыщение на `>= .seconds(Int64.max)`, проверка стоит до `components`.
- Адаптер: `WatchController.focusSection()`, в нём `currentNow` читается один раз. `load()`
  не вызывается, второго `FocusStore` нет.
- Приложение: в `PopoverModel` добавлены `focusSection`, `isFocusExpanded` и
  `setFocusExpanded(_:)`. Секция перестраивается ровно в двух точках, open и expand, по одной
  строке лога на каждую перестройку. Имена резолвятся по объединению ключей правил и строк
  сводки. В `PopoverView` новая приватная вью `FocusFold`: `DisclosureGroup` + `Grid`, она
  только читает модель.
- Тесты: новый сьют `FocusSectionTests` (6 тестов), в конец `FocusSummaryTests` дописаны 2
  теста. Прогон: 6/6 и 27/27 (25 + 2). Три мутации убиты, после каждой файл восстановлен,
  shasum совпал.

Запрещённое не выполнялось: `./build.sh` не запускался; приложение не запускалось ни
через `open`, ни прямым exec, ни через `swift run`. Не было `osascript`, `launchctl`, `kill`
или `pkill`, не было безфильтрового `swift test`. Каталог данных не читался и не писался. Из git
использовались только `status`, `diff` и `diff --no-index`.

## Изменённые файлы

`git diff --stat -- Sources Tests`:

```
 Sources/Terminator/PopoverModel.swift             |  87 +++++++++++++++-
 Sources/Terminator/PopoverView.swift              | 121 ++++++++++++++++++++++
 Sources/TerminatorAppKit/WatchController.swift    |  27 +++++
 Sources/TerminatorCore/FocusSummary.swift         |   4 +
 Tests/TerminatorCoreTests/FocusSummaryTests.swift |  29 ++++++
 5 files changed, 265 insertions(+), 3 deletions(-)
```

Новые файлы (untracked, `git status --short` → `??`):

```
?? Sources/TerminatorCore/FocusSection.swift          (58 строк)
?? Tests/TerminatorCoreTests/FocusSectionTests.swift  (296 строк)
```

Плюс этот отчёт.

| Файл | Что изменено |
|---|---|
| `Sources/TerminatorCore/FocusSection.swift` | новый: `enum FocusSection: Equatable, Sendable { hidden, unreadable, summary(FocusSummary) }` и чистый `init(recorded:accrued:quarantine:config:now:)`. Порядок веток: карантин → сводка суммы → пустые строки = hidden. Только Foundation |
| `Sources/TerminatorCore/FocusSummary.swift` | +2 строки кода (ветки насыщения в `cellText` и `totalText`) и +2 строки док-комментария. Больше ничего |
| `Sources/TerminatorAppKit/WatchController.swift` | один новый `public func focusSection() -> FocusSection` после `flushFocus()`. Остальное не тронуто |
| `Sources/Terminator/PopoverModel.swift` | приватный логгер `focusSectionLog` (категория `focus`); `private(set) var focusSection = .hidden`; `private(set) var isFocusExpanded = false`; `setFocusExpanded(_:)`; `rebuildFocusSection(trigger:)` со строкой лога; вызов перестройки в `popoverDidOpen()` между `refresh()` и `resolveDisplayNames()`; объединение идентификаторов в `resolveDisplayNames()` и его док-комментарий |
| `Sources/Terminator/PopoverView.swift` | `FocusFold(model: model)` в `content(_:)` между блоком `if let notice` и `Divider()`, вне ветки `state.isEmpty`. Новая `private struct FocusFold` |
| `Tests/TerminatorCoreTests/FocusSectionTests.swift` | новый сьют «Секция фокуса», 6 тестов, свои приватные хелперы |
| `Tests/TerminatorCoreTests/FocusSummaryTests.swift` | в конец сьюта дописаны `totalSaturatesInsteadOfTrapping` и `cellSaturatesInsteadOfTrapping`, `numstat`: `29 0` (ни одной удалённой строки) |

## Изменения поведения

- **Секция «Focus»** в поповере между строкой `notice` и разделителем над строкой автозапуска.
  - hidden: не рисуется ничего. `FocusFold.body` возвращает `EmptyView()`.
  - unreadable: заголовок `Focus`. В раскрытом виде одна строка-пояснение.
  - summary: заголовок `Focus` плюс `recordedDaysText` вторичным стилем. В раскрытом виде
    сетка: пустая ячейка, семь `DayKey.day`, `total`; дальше все `summary.rows` в порядке
    сводки. Под сеткой две подписи.
- Сводка строится в `PopoverModel` ровно в двух местах: в `popoverDidOpen()` (trigger=open) и в
  `setFocusExpanded(true)`, но только если до этого секция была свёрнута (trigger=expand).
  Повторная установка того же значения ничего не строит. Сворачивание тоже ничего не строит.
- Каждое построение пишет одну строку, категория `focus`, уровень `.notice`, `privacy: .public`
  на всех четырёх интерполяциях:
  `focus summary built: trigger=<open|expand> section=<hidden|unreadable|summary> rows=<n> recorded=<k>`.
  Для hidden и unreadable пишется `rows=0 recorded=0`.
- `resolveDisplayNames()` теперь резолвит имена и для строк сводки из истории без правила. Он
  вызывается после каждой перестройки.
- `FocusSummary.totalText` / `cellText` на `>= .seconds(Int64.max)` возвращают
  `≥2562047788015215 h` / `≥153722867280912930` вместо краха процесса. Ниже границы вывод прежний.

## Доказательства валидации

Все выводы полностью лежат в `<scratch>` =
`/private/tmp/claude-502/-Users-as-sorokin-Developer-own-terminator/effe4dff-4ac8-4e1a-8323-16834af04454/scratchpad/`.
Оболочка zsh: код возврата взят через `${pipestatus[1]}`.

### 0. Базовая линия до изменений

`swift test --filter FocusSummaryTests` до первой правки:

```
Build complete! (0.18s)
Test Suite 'Selected tests' started at 2026-09-18 09:35:44.122.
Test Suite 'TerminatorPackageTests.xctest' started at 2026-09-18 09:35:44.123.
Test Suite 'TerminatorPackageTests.xctest' passed at 2026-09-18 09:35:44.123.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
...
◇ Suite "Сводка фокуса" started.
...
✔ Suite "Сводка фокуса" passed after 0.001 seconds.
✔ Test run with 25 tests in 1 suite passed after 0.001 seconds.
EXIT=0
```

Базовой поломки нет.

### 1. `swift build`

Первый прогон после всех правок. Он перекомпилировал все пять изменённых исходников (файл
`build-debug.txt`):

```
$ swift build 2>&1 | tee <scratch>/build-debug.txt; echo "EXIT=${pipestatus[1]}"
[0/1] Planning build
Building for debugging...
[0/7] Write sources
[3/7] Write swift-version--58304C5D6DBC2206.txt
[5/10] Emitting module TerminatorCore
[6/10] Compiling TerminatorCore FocusSummary.swift
[7/10] Compiling TerminatorCore FocusSection.swift
[8/18] Compiling TerminatorAppKit FrontmostFocusObserver.swift
[9/18] Compiling TerminatorAppKit EngineLogRenderer.swift
[10/18] Compiling TerminatorAppKit LoginItemService.swift
[11/18] Emitting module TerminatorAppKit
[12/18] Compiling TerminatorAppKit ProcessLaunchTime.swift
[13/18] Compiling TerminatorAppKit QuitSender.swift
[14/18] Compiling TerminatorAppKit WatchController.swift
[15/18] Compiling TerminatorAppKit RunningApplicationsObserver.swift
[16/22] Compiling Terminator TerminatorApp.swift
[17/22] Emitting module Terminator
[18/22] Compiling Terminator PopoverModel.swift
[19/22] Compiling Terminator PopoverView.swift
[19/22] Write Objects.LinkFileList
[20/22] Linking Terminator
[21/22] Applying Terminator
Build complete! (2.94s)
EXIT=0
$ grep -c 'warning:' <scratch>/build-debug.txt
0
```

Финальный прогон после отката мутаций (`build-debug-final.txt`): `Build complete! (0.88s)`,
`EXIT=0`, `grep -c 'warning:'` → `0`.

### 2. `swift build -c release`

Первый прогон после всех правок, все три таргета (`build-release.txt`):

```
$ swift build -c release 2>&1 | tee <scratch>/build-release.txt; echo "EXIT=${pipestatus[1]}"
[0/1] Planning build
Building for production...
[0/6] Write sources
[3/6] Write swift-version--58304C5D6DBC2206.txt
[5/7] Compiling TerminatorCore AwakeInstant.swift
[6/8] Compiling TerminatorAppKit EngineLogRenderer.swift
[7/9] Compiling Terminator PopoverModel.swift
[7/9] Write Objects.LinkFileList
[8/9] Linking Terminator
Build complete! (8.45s)
EXIT=0
$ grep -c 'warning:' <scratch>/build-release.txt
0
```

Release собирается whole-module, поэтому одно имя файла на таргет означает компиляцию всего
модуля. Финальный прогон после отката (`build-release-final.txt`): `Build complete! (3.77s)`,
`EXIT=0`, `grep -c 'warning:'` → `0`.

### 3. `swift test --filter FocusSectionTests`

Финальный прогон после отката мутаций, дословно (строки `[n/m]` сборки опущены):

```
Building for debugging...
Build complete! (0.45s)
Test Suite 'Selected tests' started at 2026-09-18 09:43:29.890.
Test Suite 'TerminatorPackageTests.xctest' started at 2026-09-18 09:43:29.891.
Test Suite 'TerminatorPackageTests.xctest' passed at 2026-09-18 09:43:29.891.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'Selected tests' passed at 2026-09-18 09:43:29.892.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
◇ Test run started.
↳ Testing Library Version: 1902
↳ Target Platform: arm64e-apple-macos14.0
◇ Suite "Секция фокуса" started.
◇ Test sectionAddsUnflushedAccrualToRecordedHistory() started.
◇ Test sectionEqualsSummaryOfCombinedRollup() started.
◇ Test accrualOnADayMissingFromTheFileCountsAsRecorded() started.
◇ Test disabledRuleAloneDoesNotShowTheSection() started.
◇ Test noRowsHidesTheSection() started.
◇ Test quarantineShowsUnreadableEvenWithData() started.
✔ Test noRowsHidesTheSection() passed after 0.001 seconds.
✔ Test disabledRuleAloneDoesNotShowTheSection() passed after 0.001 seconds.
✔ Test accrualOnADayMissingFromTheFileCountsAsRecorded() passed after 0.001 seconds.
✔ Test quarantineShowsUnreadableEvenWithData() passed after 0.001 seconds.
✔ Test sectionAddsUnflushedAccrualToRecordedHistory() passed after 0.001 seconds.
✔ Test sectionEqualsSummaryOfCombinedRollup() passed after 0.001 seconds.
✔ Suite "Секция фокуса" passed after 0.001 seconds.
✔ Test run with 6 tests in 1 suite passed after 0.001 seconds.
EXIT=0
```

Какие сьюты выполнились: один swift-testing сьют «Секция фокуса». XCTest — `Executed 0 tests`.

### 4. `swift test --filter FocusSummaryTests`

Финальный прогон после отката мутаций (`test-summary-final.txt`). Строки `started` опущены,
результаты дословно:

```
Build complete! (0.11s)
Test Suite 'Selected tests' started at 2026-09-18 09:43:30.562.
Test Suite 'TerminatorPackageTests.xctest' started at 2026-09-18 09:43:30.563.
Test Suite 'TerminatorPackageTests.xctest' passed at 2026-09-18 09:43:30.563.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'Selected tests' passed at 2026-09-18 09:43:30.563.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
◇ Test run started.
◇ Suite "Сводка фокуса" started.
✔ Test totalSaturatesInsteadOfTrapping() passed after 0.001 seconds.
✔ Test windowCrossesDaylightSavingCorrectly() passed after 0.001 seconds.
✔ Test cellsTruncateDownNeverUp() passed after 0.001 seconds.
✔ Test identifiersMatchExactlyNotByPrefixOrCase() passed after 0.001 seconds.
✔ Test subMinuteRendersAsLessThanOne() passed after 0.001 seconds.
✔ Test orderUsesExactTotalsNotWholeSeconds() passed after 0.001 seconds.
✔ Test orderIsTotalDescendingThenBundleIdentifier() passed after 0.001 seconds.
✔ Test rowsExcludeDataOutsideWindow() passed after 0.001 seconds.
✔ Test missingDayIsNilNotZero() passed after 0.001 seconds.
✔ Test windowIsSevenDaysEndingToday() passed after 0.001 seconds.
✔ Test subMillisecondRemainderSurvivesSummation() passed after 0.001 seconds.
✔ Test zeroValuedEntryStillProducesARow() passed after 0.001 seconds.
✔ Test totalTextCoversEveryUnit() passed after 0.001 seconds.
✔ Test subSecondTotalIsNotZero() passed after 0.001 seconds.
✔ Test enabledRuleIgnoresDataOutsideTheWindow() passed after 0.001 seconds.
✔ Test rowsIncludeDataOnOldestWindowDay() passed after 0.001 seconds.
✔ Test rowsExcludeDisabledRuleWithoutData() passed after 0.001 seconds.
✔ Test cellSaturatesInsteadOfTrapping() passed after 0.001 seconds.
✔ Test rowsIncludeEnabledRuleWithNoData() passed after 0.001 seconds.
✔ Test recordedDayWithoutAppIsZero() passed after 0.001 seconds.
✔ Test zeroTotalRowsAreOrderedByIdentifier() passed after 0.001 seconds.
✔ Test summaryTypesConformToEquatableAndSendable() passed after 0.001 seconds.
✔ Test rowsIncludeHistoryWithoutARule() passed after 0.001 seconds.
✔ Test emptyDayKeyShowsZeroInCells() passed after 0.001 seconds.
✔ Test enabledRulesSurviveAnEmptyWindow() passed after 0.001 seconds.
✔ Test rowSetIsNotTruncated() passed after 0.001 seconds.
✔ Test denominatorCountsRecordedDaysOnly() passed after 0.001 seconds.
✔ Suite "Сводка фокуса" passed after 0.001 seconds.
✔ Test run with 27 tests in 1 suite passed after 0.001 seconds.
EXIT=0
```

Выполнился один сьют «Сводка фокуса». Проверка на `ConfigStore`:
`grep -l 'ConfigStore' <scratch>/test-section-final.txt <scratch>/test-summary-final.txt` →
пусто, rc=1. **Оговорка:** в *первом* прогоне `--filter FocusSectionTests` (`test-section.txt`)
сборочная часть содержит строку `[9/15] Compiling TerminatorCoreTests ConfigStoreTests.swift`.
`swift test` компилирует весь тестовый таргет, но это компиляция, а не исполнение. Исполнялся
только сьют «Секция фокуса», XCTest показал `Executed 0 tests`. TASK-108 работала при том же
ограничении.

### 5. `scripts/check-forbidden.sh`

```
$ scripts/check-forbidden.sh; echo "EXIT=$?"
OK:    запрещённых конструкций не найдено
EXIT=0
```

### 6. Мутации

shasum до мутаций (`sha-before.txt`) и после третьего отката (`sha-after.txt`):

```
4fb20b57f4045db263f6d32ebdc5cccc85be3c4b  Sources/TerminatorCore/FocusSection.swift
48d51d1938be8b6463e798fd79fa6dc682213cf6  Sources/TerminatorCore/FocusSummary.swift
$ diff sha-before.txt sha-after.txt && echo SHA_MATCH
SHA_MATCH
```

Откат делался обратной правкой строки. `git checkout`/`stash` не использовались.

**M1. `FocusSection` игнорирует карантин.** Правка:
`guard quarantine == nil else {` → `guard quarantine == nil || true else {`. Затем
`swift test --filter FocusSectionTests` (`mut1.txt`), `EXIT=1`:

```
✘ Test quarantineShowsUnreadableEvenWithData() recorded an issue at FocusSectionTests.swift:41:13: Expectation failed: (section → .summary(TerminatorCore.FocusSummary(days: [2026-09-11, 2026-09-12, 2026-09-13, 2026-09-14, 2026-09-15, 2026-09-16, 2026-09-17], recordedDayCount: 2, rows: [TerminatorCore.FocusSummaryRow(bundleIdentifier: "ru.keepcoder.Telegram", total: 630.0 seconds, perDay: [nil, nil, nil, nil, Optional(600.0 seconds), nil, Optional(30.0 seconds)])]))) == .unreadable
[второе issue — та же строка 41:13 с тем же текстом, здесь сокращено; полностью в mut1.txt]
✘ Test quarantineShowsUnreadableEvenWithData() failed after 0.004 seconds with 2 issues.
✘ Test run with 6 tests in 1 suite failed after 0.004 seconds with 2 issues.
```

Два issue дали оба случая `FocusLoadFailure` (`undecodableBytes` и
`schemaVersionFromTheFuture`). Остальные пять тестов прошли. После отката
`shasum FocusSection.swift` = `4fb20b57f4045db263f6d32ebdc5cccc85be3c4b`, совпадает.

**M2. `FocusSection` сводит только `recorded`.** Правка:
`FocusSummary(rollup: recorded.adding(accrued), …)` → `FocusSummary(rollup: recorded, …)`.
Затем `swift test --filter FocusSectionTests` (`mut2.txt`), `EXIT=1`:

```
✘ Test sectionAddsUnflushedAccrualToRecordedHistory() recorded an issue at FocusSectionTests.swift:151:9: Expectation failed: (row.perDay[today] → 100.0 seconds) == (.seconds(130) → 130.0 seconds)
✘ Test sectionAddsUnflushedAccrualToRecordedHistory() recorded an issue at FocusSectionTests.swift:153:9: Expectation failed: (row.total → 700.0 seconds) == (.seconds(730) → 730.0 seconds)
✘ Test sectionAddsUnflushedAccrualToRecordedHistory() failed after 0.001 seconds with 2 issues.
✘ Test accrualOnADayMissingFromTheFileCountsAsRecorded() recorded an issue at FocusSectionTests.swift:180:9: Expectation failed: (summary.recordedDayCount → 1) == 2
✘ Test quarantineShowsUnreadableEvenWithData() recorded an issue at FocusSectionTests.swift:56:9: Expectation failed: (row.total → 600.0 seconds) == (.seconds(630) → 630.0 seconds)
✘ Test sectionEqualsSummaryOfCombinedRollup() failed after 0.006 seconds with 3 issues.
✘ Test run with 6 tests in 1 suite failed after 0.006 seconds with 9 issues.
```

Названный тест падает. Кроме него мутанта ловят ещё три теста (всего 9 issue, полный текст в
`mut2.txt`). После отката `shasum FocusSection.swift` =
`4fb20b57f4045db263f6d32ebdc5cccc85be3c4b`, совпадает.

**M3. Из `totalText` убрана ветка насыщения.** Удалена строка
`if duration >= .seconds(Int64.max) { return "\u{2265}\(Int64.max / 3600) h" }`. Затем
`swift test --filter FocusSummaryTests` (`mut3.txt`), `EXIT=1`. Процесс теста упал:

```
◇ Test totalSaturatesInsteadOfTrapping() started.
Swift/Integers.swift:3539: Fatal error: Not enough bits to represent the passed value
error: Process '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper --test-bundle-path /Users/as.sorokin/Developer/own/terminator/.build/arm64-apple-macosx/debug/TerminatorPackageTests.xctest/Contents/MacOS/TerminatorPackageTests --filter FocusSummaryTests /Users/as.sorokin/Developer/own/terminator/.build/arm64-apple-macosx/debug/TerminatorPackageTests.xctest/Contents/MacOS/TerminatorPackageTests --testing-library swift-testing' exited with unexpected signal code 5
```

У `totalSaturatesInsteadOfTrapping` нет строки `passed`, итоговой строки `Test run with …`
тоже нет: процесс умер. Строка краха:
`Swift/Integers.swift:3539: Fatal error: Not enough bits to represent the passed value`.
После отката `shasum FocusSummary.swift` = `48d51d1938be8b6463e798fd79fa6dc682213cf6`,
совпадает.

### 7. Грепы по диффу

Дифф кода: `git diff -- Sources Tests` плюс `git diff --no-index /dev/null <file>` для двух
новых файлов, всего 756 строк (`code-diff.txt`). Добавленные строки лежат в `added-lines.txt`,
их 619.

```
grep -cF 'focusStore.load' -> 0
grep -cF 'FocusStore(' -> 0
grep -cF 'UserDefaults' -> 0
grep -cF '@AppStorage' -> 0
grep -cF '@SceneStorage' -> 0
grep -cF 'ScrollView' -> 0
grep -cF 'Calendar.current' -> 0
grep -cF '86400' -> 0
grep -cF 'Bundle.module' -> 0
grep -cF '.prefix(' -> 0
grep -ciE 'productiv|efficien|wasted|attention|score|goal|streak' -> 0
```

По всему диффу вместе с контекстом и удалёнными строками:

```
$ grep -nF -e 'focusStore.load' -e 'FocusStore(' -e 'UserDefaults' -e '@AppStorage' -e '@SceneStorage' -e 'ScrollView' -e 'Calendar.current' -e '86400' -e 'Bundle.module' -e '.prefix(' code-diff.txt
fixed_rc=1
$ grep -niE 'productiv|efficien|wasted|attention|score|goal|streak' code-diff.txt
words_rc=1
```

Удалённых строк во всём диффе три, и все в `resolveDisplayNames()`:

```
-    /// Резолв имён — **одно чтение на открытие поповера, а не на кадр**.
-        resolved.reserveCapacity(config.rules.count)
-        for bundleIdentifier in config.rules.keys {
```

### 8. Вью: ни `focusSection()`, ни `FocusSummary(`

```
$ grep -nF -e 'focusSection()' -e 'FocusSummary(' Sources/Terminator/PopoverView.swift
rc=1
```

Замыкание `TimelineView` не изменилось:
`TimelineView(.periodic(from: .now, by: 1)) { context in content(model.state(at: context.date)) }`.
`FocusFold` читает `model.focusSection`, `model.isFocusExpanded` и
`model.displayName(for:)`, а пишет только через `model.setFocusExpanded` в сеттере `Binding`.
`FocusSummary.cellText` и `FocusSummary.totalText` — статические форматтеры, не
инициализатор, и `FocusSummary(` они не содержат.

### 9. Строки дословно

`grep -nF` по `Sources/Terminator/PopoverView.swift`:

```
--- Text("Focus")
342:                Text("Focus")
360:                    Text("Focus")
--- Minutes frontmost per day. Totals are exact.
349:                    Text("Minutes frontmost per day. Totals are exact.")
--- — means nothing was recorded that day: Terminator wasn't running, or no watched app was frontmost. It can't tell which.
353:                    Text("— means nothing was recorded that day: Terminator wasn't running, or no watched app was frontmost. It can't tell which.")
--- The focus file could not be read when Terminator started. It was left untouched. Fix it by hand, then relaunch Terminator.
336:                Text("The focus file could not be read when Terminator started. It was left untouched. Fix it by hand, then relaunch Terminator.")
--- Text(summary.recordedDaysText)
361:                    Text(summary.recordedDaysText)
--- Text("total")
391:                Text("total")
```

Для надёжности три длинные строки взяты `sed` прямо из строк 142, 143 и 145 пакета и
проверены `grep -cF -- "\"<строка>\""`. Каждая дала `1`. Первый символ второй подписи в
байтах: `e280 94`, то есть U+2014.

Насыщение проверено тестами дословно, литералы `"≥2562047788015215 h"`,
`"≥153722867280912930"`, `"2562047788015215 h 30 m"` и `"153722867280912930"`, плюс
`unicodeScalars.first?.value == 0x2265`.

### 10. Неделя не тронута

До начала работы (09:34:44 EET):

```
-rwxr-xr-x@ 1 as.sorokin  staff  1719504 Sep 15 13:20 build/Terminator.app/Contents/MacOS/Terminator
925 /Users/as.sorokin/Developer/own/terminator/build/Terminator.app/Contents/MacOS/Terminator
pgrep_rc=0
```

После всей работы, после финальных сборок и тестов:

```
-rwxr-xr-x@ 1 as.sorokin  staff  1719504 Sep 15 13:20 build/Terminator.app/Contents/MacOS/Terminator
925 /Users/as.sorokin/Developer/own/terminator/build/Terminator.app/Contents/MacOS/Terminator
pgrep_rc=0
```

Строка `Applying Terminator` в выводе `swift build` относится к `.build/`, а не к `build/`: mtime
бинаря в бандле остался `Sep 15 13:20`.

## Acceptance criteria

| # | Критерий | Статус | Чем подтверждён |
|---|---|---|---|
| 1 | `FocusSectionTests`: шесть тестов, зелёные | выполнен | §3: `Test run with 6 tests in 1 suite passed`, EXIT=0 |
| 2 | `FocusSummaryTests`: два новых зелёные, прежние 25 зелёные и не изменены | выполнен | §4: `27 tests in 1 suite passed`; `git diff --numstat` → `29 0`; единственный хунк `@@ -746,4 +746,33 @@` стоит после последнего прежнего теста |
| 3 | Три мутации с дословным отказом и откатом, shasum совпал | выполнен | §6: M1 и M2 упали на названных тестах; M3 уронила процесс (`Fatal error: Not enough bits…`, signal 5); `SHA_MATCH` |
| 4 | `swift build` и `-c release` зелёные, 0 `warning:` | выполнен | §1, §2: EXIT=0, `grep -c` → 0 в обоих прогонах каждой конфигурации |
| 5 | `scripts/check-forbidden.sh` зелёный | выполнен | §5: `OK`, EXIT=0 |
| 6 | Грепы по диффу пусты | выполнен | §7: все счётчики 0; по полному диффу rc=1 |
| 7 | В `TimelineView` и во всём `PopoverView.swift` нет `focusSection()` / `FocusSummary(` | выполнен | §8: rc=1 |
| 8 | Строки совпадают посимвольно | выполнен | §9: grep каждой строки плюс сверка с текстом пакета; U+2014 подтверждён байтами |
| 9 | Неделя не тронута: mtime `Sep 15 13:20`, ровно pid 925 | выполнен | §10: до и после одинаково |

## Не запускалось

- **Ручной чеклист фазы B, целиком.** Из профиля `manual-checklist` я не засчитываю ничего.
  Человек проверит в фазе B, после закрытия недели:
  - вёрстку сетки в 340 pt. Ширина имени против семи числовых колонок и итога; числовые ячейки
    стоят с `.fixedSize()`, так что уступать место и усекаться посередине будет колонка имени;
  - высоту поповера при раскрытии секции на уже открытом окне: растёт, обрезается или прыгает
    (карточка, пункт 5);
  - что строка `focus summary built: …` пишется одна на открытие или раскрытие, а не раз в
    секунду, и в ней нет `<private>` (пункты 6 и 8, через `/usr/bin/log show`);
  - что в состоянии hidden не видно ни заголовка, ни лишнего отступа. `EmptyView` внутри
    `VStack(spacing: 12)` по ожиданию места не занимает, но на экране это не проверено;
  - раскрытие через `DisclosureGroup`: на macOS переключает, возможно, только треугольник, а не
    текст заголовка. Как это ощущается, решит чеклист;
  - что раскрытие переживает закрытие и повторное открытие поповера и сбрасывается при
    перезапуске (пункт 7).
- `./build.sh`, запуск приложения, безфильтровый `swift test` и `ConfigStoreTests` запрещены
  в фазе A. Путь `PopoverModel`/`PopoverView`/`WatchController.focusSection()` покрыт только
  компиляцией (debug и release, 0 warnings) и ревью. Логика выбора состояния и суммы свёрток
  покрыта юнит-тестами ядра. Остаточный риск в вёрстке и поведении окна, и его закрывает фаза B.

## Проверка скоупа

`git status --short` после работы:

```
 M Sources/Terminator/PopoverModel.swift
 M Sources/Terminator/PopoverView.swift
 M Sources/TerminatorAppKit/WatchController.swift
 M Sources/TerminatorCore/FocusSummary.swift
 M Tests/TerminatorCoreTests/FocusSummaryTests.swift
 M docs/ai/current-context.md
 M docs/ai/execution-state.md
 M docs/ai/handoff/current-task-packet.md
RM docs/product/backlog/tasks/deferred/TASK-101-statistics-ui.md -> docs/product/backlog/tasks/in-progress/TASK-101-statistics-ui.md
 M docs/product/decisions/active/DEC-004-no-warning.md
 M docs/product/decisions/active/DEC-005-focus-statistics.md
 M docs/product/decisions/active/DEC-006-anti-circumvention-non-goal.md
 M docs/product/decisions/index.md
 M docs/product/roadmap/stages/02-statistics.md
?? Sources/TerminatorCore/FocusSection.swift
?? Tests/TerminatorCoreTests/FocusSectionTests.swift
```

Все `docs/`-строки, кроме этого отчёта, были грязными ещё до начала работы. Это правки
оркестратора, я их не трогал. Сам отчёт tracked, поэтому в `status` он появится как
`M docs/ai/handoff/current-execution-report.md`.

- Запрещённые файлы (`FocusStore.swift`, `FocusFormat.swift`, `FocusLedger.swift`,
  `FocusRollup.swift`, `WatchEngine.swift`, `PopoverViewModel.swift`, `TerminatorApp.swift`,
  `build.sh`, `Package.swift`, `scripts/`, `Packaging/`, `build/`) в диффе отсутствуют. Их я
  только читал, чтобы проверить стоп-условия: `focusRollup(at:)` не `mutating` и вызывает
  неизменяющий `FocusLedger.rollup(in:at:)`; `FocusStore.recorded` и `quarantine` публичны на
  чтение; `FocusLoadFailure` — `Equatable, Sendable`.
- В `WatchController.swift` добавлен только метод. `start`, `flushFocus`, `reloadFromDisk`,
  таймеры и свойства не тронуты: в хунке `@@ -239,6 +239,33 @@` одни добавления.
- В `FocusSummary.swift` только 4 добавленные строки: две ветки и две строки док-комментария.
- `git commit`, `add`, `stash` и `checkout -- <file>` не выполнялись.
- Swift 6: никаких `@unchecked Sendable`, `@preconcurrency`, `nonisolated(unsafe)`.

## Риски

- **Вёрстка не видна.** Как сетка из 9 колонок ляжет в 340 pt минус отступы и индентацию
  `DisclosureGroup`, не измерено. При больших числах колонка имени может сжаться почти до
  нуля. Это находка для чеклиста, а не повод превентивно менять вёрстку: пакет прямо запрещает
  подгонять её вслепую.
- **Строковые литералы в `Text("…")`** идут как `LocalizedStringKey`, как и существующий
  `Text("Terminator asks the apps …")`. Файла локализации нет, поэтому показывается ключ как
  есть. Markdown-символов (`* _ \` [ ]`) в строках нет. Числа дня выводятся через
  `Text(String(day.day))`, то есть дословно, без локализованного форматирования.
- **Лишние утверждения сверх пакета.** Они усиливают тесты и ничего не меняют:
  - в обоих тестах насыщения есть точка `.seconds(Int64.max) - .nanoseconds(1)`. Она фиксирует
    точность границы снизу: ловит `> .seconds(Int64.max - 1)`, который три пакетных входа
    пропустили бы;
  - в `quarantineShowsUnreadableEvenWithData` и `disabledRuleAloneDoesNotShowTheSection` есть
    контрольный прогон без карантина или с включённым правилом;
  - в `noRowsHidesTheSection` три входа без строк: всё пусто, данные только вне окна, пустой
    ключ дня;
  - в `sectionEqualsSummaryOfCombinedRollup` проверено, что сводка отличается от сводки
    каждого слагаемого по отдельности и от сводки с пустым конфигом.
- **Пустой ключ дня при нуле строк даёт `hidden`**, хотя знаменатель был бы `1 of 7`. Это
  буквальное следование правилу «ноль строк → hidden» из пакета, и тест его закрепляет. Если
  оркестратор видит это иначе, это решение, а не баг реализации.

## Незавершённое и follow-up

- Фаза B целиком: сборка, замена резидента, чеклист 0–11 из карточки. Она не моя и ждёт
  закрытия недели.
- Документы (execution-log, state, перемещение карточки) пакет мне не поручал, они не
  тронуты.
- Возможный кандидат в карточку, решает оркестратор: пункт 5 фазы B (высота
  `MenuBarExtra(.window)` при растущем содержимом) — единственное неизмеренное платформенное
  поведение в этой задаче. Его место — findings, рукой оркестратора.
