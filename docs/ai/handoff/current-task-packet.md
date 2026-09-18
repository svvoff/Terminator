# Task Packet — TASK-101, фаза A

## Задача

TASK-101 — Statistics UI: секция «Focus» в поповере. **Только фаза A**: код и тесты, headless.
Карточка: `docs/product/backlog/tasks/in-progress/TASK-101-statistics-ui.md`.

## Исполнение

Маршрут: делегировано `claude-code` (субагент). Продакшн-код в трёх таргетах плюс ядро, а
`CLAUDE.md` прямо относит Swift-код к делегируемому.
Отчёт в: `docs/ai/handoff/current-execution-report.md`, по шаблону
`docs/ai/execution-report-template.md`.

## ⛔ Самые дорогие ошибки в этой задаче

1. **Тронуть неделю сбора Stage 1.** На машине работает резидент (pid 925, запущен launchd).
   Идёт неделя, от которой зависят критерии выхода Stage 1. `./build.sh` начинается с
   `rm -rf build/Terminator.app`: это каталог, из которого работает резидент, и на него же указывает
   plist автозапуска. Любой запуск приложения (`open`, прямой exec, `swift run`) поднимает второй
   экземпляр, а два экземпляра молча затирают накопленные секунды друг друга (findings §12).
   Безфильтровый `swift test` гоняет `ConfigStoreTests`, а `ConfigStore` пишет в ту же подсистему
   логов, откуда снимается неделя. **Поэтому: никакого `./build.sh`, никакого запуска, `swift test`
   только с фильтром, который не выбирает `ConfigStoreTests`, никакого доступа к
   `~/Library/Application Support/com.svvoff.terminator/`.** Цена ошибки — неделя данных автора,
   а не эта карточка.
2. **Второй `focusStore.load()` или второй `FocusStore`.** `flush` пишет
   `recorded.adding(accrued)`, а `recorded` меняется только в `load()`. Повторное чтение делает
   так, что `recorded` уже содержит накопленное этим запуском, и каждый следующий слив записывает
   его дважды — безусловно и молча. Симметрия с `reloadFromDisk()` конфига — ловушка. Отдельный
   `FocusStore`, читающий файл сам, показал бы не то число, которое продукт пишет. Любое из этого
   в диффе — отказ в приёмке.
3. **Строить сводку в теле вью.** `content(_:)` в `PopoverView` вызывается изнутри
   `TimelineView(.periodic(from: .now, by: 1))`, то есть раз в секунду. Сводка, построенная там,
   пересортировывает строки под курсором по мере роста сегодняшнего числа, а в UI этого не видно.
   Сводка строится ровно в двух точках модели и хранится. Вью её только читает.

## Цель

Показать сводку фокуса за семь дней, которую уже считает ядро (`FocusSummary`, TASK-108), в
существующем поповере как сворачиваемую секцию «Focus». Новой логики две: **какую свёртку
сводить** и **какое из трёх состояний показать**. Обе живут в `TerminatorCore` и покрыты
тестами. Плюс одно решение, закрывающее слепое пятно TASK-108: оба форматтера сводки
насыщаются вместо падения.

## Контекст

**Что есть.** `Sources/TerminatorCore/FocusSummary.swift` (TASK-108, принят 2026-09-17, 25 тестов):

- `FocusSummary(rollup:config:now:)`;
- `days: [DayKey]`: семь дней, старший первым, последний — сегодня;
- `recordedDayCount`;
- `rows: [FocusSummaryRow]`: итог по убыванию, при ничьей `bundleIdentifier` по возрастанию;
- `FocusSummaryRow` с полями `bundleIdentifier`, `total: Duration` и `perDay: [Duration?]`
  (`nil` — день не записан);
- `static cellText(_:)`, `static totalText(_:)`, `recordedDaysText`.

Тип `Equatable, Sendable`. Публичная документация `rows` оговаривает предусловие: строить
сводку один раз на открытие из замороженного снимка.

**Какую свёртку сводить.** `FocusStore.recorded` — файл, как он прочитан при старте процесса.
`engine.focusRollup(at: now)` — накопленное этим запуском, включая открытый отрезок. Файл один
отстаёт до 60 с (интервал слива). Движок один теряет все прошлые запуски. Их сумма
`recorded.adding(accrued)` — ровно то, что запишет следующий слив. Оба источника живут внутри
`WatchController` (`Sources/TerminatorAppKit/WatchController.swift`). Там же единственная точка
чтения часов, `private var currentNow: Now`.

**Карантин хранилища фокуса.** `FocusStore.load()` вызывается один раз за жизнь процесса, в
`WatchController.start()`. В карантине `recorded` пуст, а каждый слив отказывает. Сводка пустой
истории плюс накопленного этим запуском выглядела бы как тонкая, но настоящая неделя. Поэтому
карантин показывает строку, а не таблицу. `FocusLoadFailure` —
`Sources/TerminatorCore/FocusFormat.swift:8`, случаи `.undecodableBytes(message:)` и
`.schemaVersionFromTheFuture(found:supported:)`.

**Имена приложений.** `PopoverModel.resolveDisplayNames()` обходит только `config.rules.keys`.
Строка сводки из истории без правила осталась бы с голым bundle id, пока у соседей имена.

**Насыщение.** `FocusSummary.totalText` падает на итоге больше `Int64.max` секунд, потому что
переполняется `Duration.components`. Декодер принимает любую неотрицательную `Int` на день, так
что двух руками исправленных дней ≥ 2⁶² в окне достаточно. Складка делает этот вызов
достижимым из файла, который пользователя приглашают править. Падение убивает резидента, а
`KeepAlive` намеренно нет (DEC-006): лимитер выключен до следующего входа. Решено насыщать оба
форматтера.

**Фаз две.** Эта — A. Фаза B (сборка бандла и ручной чеклист) начнётся после закрытия недели и
не твоя. Карточка вся остаётся в `in-progress/`. Статусы ты не трогаешь.

**Findings, на которые опирается задача** (читать не обязательно, суть здесь):

- §7 — никогда не `swift run`; без `Bundle.module` и `resources:`;
- §8 — лейбл меню-бара принимает только `Text`, `Image` или `Label`, поэтому он не-цель;
- §12 — два экземпляра затирают накопленное друг друга;
- §14 — на каждой интерполяции в логе `privacy: .public`, иначе `<private>` навсегда.

**Решения** (не перерешиваются):

- DEC-004 — никаких уведомлений и бейджей. Складка — ambient status, как отсчёт;
- DEC-005 — числа фокуса — это нижняя граница внимания, а не его мера. Только наблюдаемые
  приложения;
- DEC-006 — ничего, что ловит обход: ни стриков, ни счётчиков выключений;
- DEC-008 — связывает через EPIC-04, в коде ничего не требует.

## Что читать

| Файл | Зачем | Объём |
|---|---|---|
| `docs/ai/EXECUTOR.md` | контракт и проектные запреты | 206 строк, целиком |
| карточка TASK-101 (путь выше) | контракт; разделы «Scope», «Acceptance criteria», «Executor allowed/forbidden areas» | ~300 строк |
| `Sources/TerminatorCore/FocusSummary.swift` | что уже есть и куда вставлять насыщение | 171, целиком |
| `Sources/TerminatorCore/FocusRollup.swift` | `adding(_:)`, `DayKey` | 130 |
| `Sources/TerminatorCore/Now.swift`, `RuleConfig.swift`, `Rule.swift` | как собрать вход в тестах | 38 + 40 + 104 |
| `Tests/TerminatorCoreTests/FocusSummaryTests.swift` | **строки 1–60 и 750–815**: стиль сьюта и приватные хелперы (`moment`, `instant`, `rules`, `day`). Хелперы `private`, так что в новом файле заведи свои | 815, частями |
| `Sources/TerminatorAppKit/WatchController.swift` | `focusRollup`, `focusStore`, `currentNow`, место для нового метода | 295 |
| `Sources/Terminator/PopoverModel.swift` | `popoverDidOpen()`, `resolveDisplayNames()`, стиль логгеров вверху файла | 601; нужны строки 1–195 |
| `Sources/Terminator/PopoverView.swift` | куда вставлять складку и как устроены соседние приватные вью | 329, целиком |
| `Sources/TerminatorCore/LoggingIdentity.swift` | `TerminatorLog.subsystem`, `TerminatorLog.Category.focus` | 45 |

Не читай: `macos-findings.md` целиком, архивы, другие карточки, `CLAUDE.md`.

## Требуемое поведение

### Три состояния секции

| Состояние | Когда | Что видно |
|---|---|---|
| **hidden** | не карантин и у сводки ноль строк: в окне нет данных и нет включённых правил | ничего: ни заголовка, ни разделителя, ни заглушки |
| **unreadable** | `quarantine != nil`, **даже если в свёртках есть данные** | заголовок `Focus`; в раскрытом виде одна строка (ниже) |
| **summary** | иначе | заголовок `Focus` + `recordedDaysText`; в раскрытом виде сетка и две подписи |

### Строки — дословно

- Заголовок: `Focus`. Для summary рядом вторичным стилем `summary.recordedDaysText` (например,
  `6 of 7 days recorded`).
- Раскрытый summary, сетка:
  - строка заголовков: пустая ячейка имени, семь чисел `summary.days[i].day` (день месяца) от
    старшего к сегодняшнему слева направо, затем `total`;
  - по строке на каждый элемент `summary.rows` — **в данном порядке и все**: имя (отрезолвленное,
    иначе bundle id моноширинным с усечением посередине; `.help(bundleIdentifier)` в обоих
    случаях), семь ячеек `FocusSummary.cellText(row.perDay[i])`, итог
    `FocusSummary.totalText(row.total)`.
- Под сеткой две строки подписи, дословно (первый символ второй строки — U+2014):
  - `Minutes frontmost per day. Totals are exact.`
  - `— means nothing was recorded that day: Terminator wasn't running, or no watched app was frontmost. It can't tell which.`
- Раскрытый unreadable, дословно:
  `The focus file could not be read when Terminator started. It was left untouched. Fix it by hand, then relaunch Terminator.`

### Насыщение (U+2265, без пробела после `≥`)

| Вход | `totalText` | `cellText` |
|---|---|---|
| `>= .seconds(Int64.max)` | `≥2562047788015215 h` | `≥153722867280912930` |
| `.seconds(Int64.max - 1)` | `2562047788015215 h 30 m` (обычный путь) | `153722867280912930` (обычный путь) |

Числа проверены: `Int64.max / 3600 = 2562047788015215`, `Int64.max / 60 = 153722867280912930`,
`(Int64.max - 1) % 3600 / 60 = 30`.

### Когда строится секция

Ровно в двух точках, обе в `PopoverModel`:

1. в `popoverDidOpen()`, после `refresh()` и до `resolveDisplayNames()`;
2. при переходе «свёрнуто → раскрыто» (не при каждом вызове сеттера с тем же значением).

Каждое построение пишет **одну** строку лога: категория `TerminatorLog.Category.focus`, уровень
`.notice`, `privacy: .public` на **каждой** интерполяции:

```
focus summary built: trigger=<open|expand> section=<hidden|unreadable|summary> rows=<n> recorded=<k>
```

Для hidden и unreadable значения `rows=0 recorded=0`.

### Раскрытие

`isFocusExpanded` — свойство модели, `false` при создании, только в памяти. Модель живёт в
`AppDelegate`, поэтому раскрытие переживает закрытие и повторное открытие поповера и
сбрасывается при перезапуске. Ничего не персистится.

## Требования к реализации

**1. `Sources/TerminatorCore/FocusSection.swift`** (новый файл). Форма:

```swift
public enum FocusSection: Equatable, Sendable {
    case hidden
    case unreadable
    case summary(FocusSummary)

    public init(
        recorded: FocusRollup,
        accrued: FocusRollup,
        quarantine: FocusLoadFailure?,
        config: RuleConfig,
        now: Now
    )
}
```

Порядок в инициализаторе: сначала карантин, потом
`FocusSummary(rollup: recorded.adding(accrued), config: config, now: now)`, потом пустые
строки → hidden. Только Foundation, никаких часов, диска и глобалов. Док-комментарии по-русски,
в стиле соседних файлов, со ссылками на DEC-005 и на причину каждой ветки.

**2. `FocusSummary.swift`** — только ветки насыщения в `cellText` и `totalText` (граница
`duration >= .seconds(Int64.max)`, проверяется **до** любого обращения к `components`) и по
строке в их док-комментарии. Остальное в файле не трогать.

**3. `WatchController.focusSection() -> FocusSection`** — один новый публичный метод. Внутри
**один** раз `let now = currentNow`, и этот же `now` идёт и в `engine.focusRollup(at: now)`, и в
`FocusSection(...)`. Источники: `focusStore.recorded`, `focusStore.quarantine`, `store.config`.
Док-комментарий объясняет, почему сумма, а не одно из двух, и почему здесь нет `load()`. Ничего
больше в контроллере не менять.

**4. `PopoverModel`:**

- `private(set) var focusSection: FocusSection = .hidden`;
- `private(set) var isFocusExpanded = false`;
- `func setFocusExpanded(_ expanded: Bool)` — перестраивает секцию только на переходе
  `false → true`;
- приватный метод перестройки: `focusSection = controller.focusSection()`, затем строка лога;
- `resolveDisplayNames()` обходит объединение `config.rules.keys` и `bundleIdentifier` строк
  секции (если это summary). Вызывается после каждой перестройки. Поправь его док-комментарий:
  теперь это чтение на открытие **и на раскрытие**, и оба — дискретные события;
- новый приватный логгер в стиле двух существующих вверху файла, категория `focus`.

**5. `PopoverView`:**

- новая приватная вью (например, `FocusFold`) в стиле `LaunchAtLoginRow` и `QuarantineBanner`;
- вставляется в `content(_:)` между блоком `if let notice` и `Divider()`, вне ветки
  `state.isEmpty`, то есть в обоих состояниях списка правил;
- читает только `model.focusSection`, `model.isFocusExpanded` и `model.displayName(for:)`;
- никаких вызовов `controller`, `focusSection()` и `FocusSummary(` в вью;
- раскрытие — например, `DisclosureGroup(isExpanded: Binding(get:set:))` с сеттером
  `model.setFocusExpanded`;
- сетка — `Grid`/`GridRow` (macOS 13+, пол пакета 14), шрифт `.caption`, `.monospacedDigit()`
  на числах, ячейки выровнены по правому краю;
- ширина поповера фиксирована — 340 (`.frame(width: 340)`), отступ 14. Как оно выглядит, решит
  чеклист фазы B; не подгоняй вёрстку вслепую сложными приёмами.

**6. Тесты.**

`Tests/TerminatorCoreTests/FocusSectionTests.swift` — новый сьют `FocusSectionTests`,
swift-testing, стиль как у `FocusSummaryTests`, свои приватные хелперы. Тесты:

- `quarantineShowsUnreadableEvenWithData` — карантин плюс данные в **обеих** свёртках дают
  `.unreadable`;
- `noRowsHidesTheSection` — пустые свёртки и пустой конфиг дают `.hidden`;
- `disabledRuleAloneDoesNotShowTheSection` — правило с `enabledAt == nil` без данных даёт
  `.hidden`;
- `sectionAddsUnflushedAccrualToRecordedHistory` — в `recorded` прошлый день и 100 с сегодня у
  приложения A, в `accrued` 30 с сегодня у A. В строке A: сегодня 130 с, прошлый день целиком;
- `accrualOnADayMissingFromTheFileCountsAsRecorded` — сегодняшнего дня нет в `recorded`, он
  есть в `accrued`, и он входит в `recordedDayCount`;
- `sectionEqualsSummaryOfCombinedRollup` — `.summary(s)` и
  `s == FocusSummary(rollup: recorded.adding(accrued), config:, now:)`.

`FocusSummaryTests.swift` — **дописать в конец сьюта**, существующие тесты не трогать:

- `totalSaturatesInsteadOfTrapping` — `.seconds(Int64.max) + .seconds(Int64.max)` и
  `.seconds(Int64.max)` дают `≥2562047788015215 h`; `.seconds(Int64.max - 1)` даёт
  `2562047788015215 h 30 m`;
- `cellSaturatesInsteadOfTrapping` — те же три входа для `cellText`.

Сила каждого утверждения не должна зависеть от порядка обхода `Set` или `Dictionary`. Это урок
TASK-108: тест, названный по правилу, ловил своего мутанта через раз, потому что порядок подачи
входа до сортировки не доходил. Если утверждение имеет силу только при определённом порядке
обхода — это дефект теста.

## Не-цели

Дословно из карточки:

- no charts, bars, sparklines, or any drawn graphic;
- nothing in the menu bar label;
- no window;
- no 30 days, "all time", or range picker;
- no schema change: `currentSchemaVersion` stays 1;
- no notifications, digests, or badges;
- no streaks, counts of disabled rules, or "over the limit" figures;
- no share-of-day;
- no word implying judgement: productivity, efficiency, wasted, attention time, score, goal;
- no limit recommended from the data;
- **no persisted UI state**: no `UserDefaults`, `@AppStorage`, `@SceneStorage`, or file;
- **no `ScrollView`, no row cap, no `.prefix` on rows**;
- no change to rule rows or their order (`PopoverViewModel`), the engine, the flush path, or
  `FocusStore`/`FocusFormat`/`FocusLedger`/`FocusRollup`;
- no weekday names and no `DateFormatter`: day-of-month from `DayKey.day` only.

## Разрешённые зоны

- `Sources/TerminatorCore/FocusSection.swift` — новый.
- `Sources/TerminatorCore/FocusSummary.swift` — только ветки насыщения и строки их
  док-комментариев.
- `Tests/TerminatorCoreTests/FocusSectionTests.swift` — новый.
- `Tests/TerminatorCoreTests/FocusSummaryTests.swift` — только дописанные тесты.
- `Sources/TerminatorAppKit/WatchController.swift` — только новый метод `focusSection()`.
- `Sources/Terminator/PopoverModel.swift` — состояние фокуса, две точки перестройки, строка лога,
  объединение для имён.
- `Sources/Terminator/PopoverView.swift` — складка.
- `docs/ai/handoff/current-execution-report.md` — твой отчёт.

## Запрещённые зоны

- `FocusStore.swift`, `FocusFormat.swift`, `FocusLedger.swift`, `FocusRollup.swift`,
  `WatchEngine.swift`, `PopoverViewModel.swift`, `TerminatorApp.swift`.
- Остальной `WatchController.swift`: `start`, `flushFocus`, `reloadFromDisk`, таймеры,
  свойства.
- `build.sh`, `Package.swift`, `scripts/`, `Packaging/`, `build/`.
- `docs/` целиком, кроме твоего отчёта: карточки, решения, findings, стадии, state, log.
- Работающий резидент, пункт автозапуска, каталог данных
  `~/Library/Application Support/com.svvoff.terminator/`.
- `git commit`, `git add`, `git stash`, `git checkout -- <файл>`: дерево остаётся грязным для
  ревью.

## Acceptance criteria

По каждому пункту в отчёте: выполнен / не выполнен, с доказательством.

1. `FocusSectionTests`: шесть тестов выше, зелёные.
2. `FocusSummaryTests`: два новых теста, зелёные; все прежние 25 зелёные и **не изменены**.
3. Три мутации, каждая с дословно процитированным отказом, затем откат:
   1. `FocusSection` игнорирует карантин → падает `quarantineShowsUnreadableEvenWithData`;
   2. `FocusSection` сводит только `recorded` → падает
      `sectionAddsUnflushedAccrualToRecordedHistory`;
   3. убрана ветка насыщения в `totalText` → `totalSaturatesInsteadOfTrapping` роняет процесс
      теста. Процитируй строку краха.

   Для каждой мутации приложи `shasum` изменённого файла до мутации и после отката: они должны
   совпасть.
4. `swift build` и `swift build -c release` зелёные, **ноль** строк `warning:` в каждой (приложи
   счёт `grep -c 'warning:'`).
5. `scripts/check-forbidden.sh` зелёный.
6. Грепы по диффу (`git diff` плюс новые файлы) пусты: `focusStore.load`, `FocusStore(`,
   `UserDefaults`, `@AppStorage`, `@SceneStorage`, `ScrollView`, `Calendar.current`, `86400`,
   `Bundle.module`, `.prefix(`, и слова `productiv|efficien|wasted|attention|score|goal|streak`
   (без учёта регистра). Приложи команды и вывод.
7. Внутри замыкания `TimelineView` и во всём `PopoverView.swift` нет ни `focusSection()`, ни
   `FocusSummary(`. Приложи греп.
8. Строки из раздела «Строки — дословно» совпадают посимвольно. Приложи греп каждой.
9. Неделя не тронута. До начала работы и после неё:
   - `ls -l build/Terminator.app/Contents/MacOS/Terminator` — mtime `Sep 15 13:20`;
   - `pgrep -fl '[b]uild/Terminator.app'` — ровно pid 925.

## Валидация и доказательства

Разрешённые команды:

```bash
swift build 2>&1 | tee <scratch>/build-debug.txt; echo "EXIT=${PIPESTATUS[0]}"
grep -c 'warning:' <scratch>/build-debug.txt
swift build -c release 2>&1 | tee <scratch>/build-release.txt; echo "EXIT=${PIPESTATUS[0]}"
grep -c 'warning:' <scratch>/build-release.txt
swift test --filter FocusSummaryTests
swift test --filter FocusSectionTests
scripts/check-forbidden.sh
```

Оболочка может быть zsh. Там `PIPESTATUS` пишется как `pipestatus[1]`: проверь, что код возврата
реально получен, а не пуст. В выводе каждого `swift test --filter` должно быть видно, **какие
сьюты выполнились**. `ConfigStoreTests` среди них быть не должно.

**Запрещено в этой фазе:**

- безфильтровый `swift test`;
- `--filter`, выбирающий `ConfigStoreTests`;
- `./build.sh` в любой форме;
- `open`, прямой exec бинаря, `swift run`;
- `osascript`, `launchctl`, `pkill`, `kill`;
- любое чтение и запись каталога данных.

**Ручной чеклист (фаза B) не твой.** Из профиля `manual-checklist` ты не засчитываешь ничего. В
отчёте в разделе «не запускалось» перечисли: вёрстку сетки в 340 pt, высоту поповера при
раскрытии, одну строку лога на открытие — всё это проверит человек в фазе B.

## Уровень риска

medium. Единственная поверхность продукта, три таргета. Зон повышенного риска из `CLAUDE.md` фаза
A не касается: подпись, keychain, TCC, LaunchAgents, формат конфига и чужие процессы не
затрагиваются. `./build.sh` запрещён. Разрешение пользователя на задачу дано явно 2026-09-18.

## Стоп-условия

Остановись и напиши отчёт со статусом BLOCKED или ESCALATE, если:

- правка требует файла из запрещённых зон;
- ошибка конкурентности Swift 6 лечится только `@unchecked Sendable`, `@preconcurrency` или
  `nonisolated(unsafe)`;
- `engine.focusRollup(at:)` окажется мутирующим или с побочными эффектами;
- `FocusSummary` или `FocusLoadFailure` не `Equatable`/`Sendable`, и `FocusSection` не может ими
  быть без правки чужого файла;
- проверить поведение можно только запуском приложения;
- любой тест, кроме твоих мутаций, красный до твоих изменений — это базовая поломка, её надо
  сообщить, а не чинить;
- пакет противоречит карточке или сам себе.

## Формат отчёта

По `docs/ai/execution-report-template.md`, в `docs/ai/handoff/current-execution-report.md`.
Дословные выводы команд, а не пересказ. Отдельной секцией — список изменённых и новых файлов с
`git diff --stat` и перечнем новых файлов.
