# Отчёт об исполнении

## Задача

**TASK-007 — учёт фокуса и дневная свёртка.** Пакет: `docs/ai/handoff/current-task-packet-focus.md`
(третий параллельный поток, суффикс `-focus`).

## Кратко

Сбор фокуса реализован целиком: накопительная шкала `AwakeInstant` в `Now`, четыре входа
`EngineInput`, `FocusLedger` внутри редьюсера, свой версионированный файл `focus.json` со
слиянием по дням, адаптер KVO с четырьмя парами пауз и таймером полуночи, слив на каденции и на
`applicationWillTerminate`. UI не производится. 19 новых тестов, вся сьюта — 83 теста, зелёная.
Инвариант порядка проверен **опытом на опровержение**: перестановка слива и удаления роняет
именованный тест.

Три вещи требуют решения оркестратора, они собраны в разделе «Отступления и решения»:
семантика слияния при сливе (**сложение**, а не замещение), четвёртое поле у `FrontmostApp` и
параметр `now` у `applyConfig`. Ни одна из них не тихая: каждая описана здесь до приёмки.

## Изменённые файлы

| Файл | Что изменено |
|---|---|
| `Sources/TerminatorCore/AwakeInstant.swift` | **новый.** Момент suspending-шкалы. Ни одной конверсии в `Date` и обратно |
| `Sources/TerminatorCore/FocusRollup.swift` | **новый.** `DayKey` (локальная дата, границы дня с учётом DST) и `FocusRollup` |
| `Sources/TerminatorCore/FocusInputs.swift` | **новый.** `FrontmostApp`, `FocusPauseReason` (четыре причины, `CaseIterable`) |
| `Sources/TerminatorCore/FocusLedger.swift` | **новый.** Спан, множество пауз, начисление с расщеплением по полуночи, `endSpan` |
| `Sources/TerminatorCore/FocusFormat.swift` | **новый.** `FocusLoadFailure` + кодек файла фокуса |
| `Sources/TerminatorCore/FocusStore.swift` | **новый.** Хранилище: чтение, карантин, долговечный слив |
| `Sources/TerminatorCore/Now.swift` | Второе и третье поля (`awake`, `timeZone`), **без умолчаний**; док-комментарий переписан |
| `Sources/TerminatorCore/EngineInput.swift` | Четыре случая фокуса; «шесть входов» → «десять» |
| `Sources/TerminatorCore/WatchEngine.swift` | Одно поле `focus`, четыре ветки-делегата, `focusRollup(at:)`, **по одной вставке** в четырёх функциях удаления |
| `Sources/TerminatorAppKit/FrontmostFocusObserver.swift` | **новый.** KVO по фронтмосту, четыре пары сигналов, таймер полуночи, смена пояса, `focusLog` |
| `Sources/TerminatorAppKit/WatchController.swift` | `focusStore`, `focusObserver`, таймер каденции, `focusRollup`, `flushFocus()`, `currentNow` |
| `Sources/Terminator/TerminatorApp.swift` | `applicationWillTerminate(_:)` — одна строка `controller.flushFocus()` |
| `Tests/TerminatorCoreTests/FocusTests.swift` | **новый.** 19 тестов |
| `Tests/TerminatorCoreTests/WatchEngineTests.swift` | Хелпер `now(_:)` — механическая правка под три поля `Now` |

Файлы `docs/ai/current-context.md`, `docs/ai/execution-log/latest.md`,
`docs/ai/execution-state.md` показаны изменёнными в `git status`, но **изменены не мной**: за
время исполнения я не открывал и не правил ни одного файла в `docs/`. Дерево на старте было
объявлено чистым, значит их правил кто-то параллельно (оркестратор или соседний поток).

## Изменения поведения

**Что теперь происходит.** Наблюдатель системно смотрит за `frontmostApplication`, переводит мир
в четыре входа, редьюсер накапливает секунды по (день, bundle id) только для приложений с
**включённым** правилом, а контроллер раз в минуту (пока грязно), на смене дня и на выходе
пишет `~/Library/Application Support/com.svvoff.terminator/focus.json`.

**Две шкалы разведены типами.** `Now.wall: Date` — дедлайн, идёт во сне. `Now.awake:
AwakeInstant` — фокус, во сне стоит. Между ними нет ни одного инициализатора, преобразования
или арифметики. Дедлайн `awake` не читает; фокус `wall` использует **только** для выбора
календарного дня и пропорции расщепления, никогда как длительность.

**Инвариант порядка.** `focus.endSpan(ofSession:in:config:at:)` зовётся непосредственно перед
удалением записи во всех четырёх функциях и **читает таблицу сессий** — поэтому перестановка
строк ломает его наблюдаемо, а не только на словах (см. опыт ниже).

**Формат файла — новый контракт, утверждает оркестратор.** Имя `focus.json`, `schemaVersion: 1`,
дни ключами `YYYY-MM-DD`, длительности — целые секунды `Int`. Дословные байты приложены.

## Доказательства валидации

| Команда | Результат | Вывод |
|---|---|---|
| `swift build` | EXIT=0 | `Build complete! (0.11s)` |
| `swift build -c release` | EXIT=0 | `Build complete! (2.28s)` |
| `swift build` + `swift build -c release`, счёт `warning:` | **0** | `grep -c "warning:"` → `0` (чистая пересборка release тоже 0) |
| `swift test` | EXIT=0 | `Test run with 83 tests in 8 suites passed after 0.119 seconds.` (было 64, добавлено 19) |
| `scripts/check-forbidden.sh` | EXIT=0 | `OK:    запрещённых конструкций не найдено` |
| `./build.sh` | EXIT=0 | `--- codesign --verify --strict (терминальный шаг) ---`, отдельная проверка `codesign --verify --strict build/Terminator.app` → EXIT=0 |
| `scripts/verify-docs.sh` | 0/0 | `OK: backlog docs are consistent` / `Summary: 0 error(s), 0 warning(s).` |

### Опыт на опровержение (критерий 1)

Строки в `dropSessions` переставлены местами (слив **после** удаления), прогон одного теста:

```
✘ Test focusSpanIsFlushedBeforeProcessIsDropped() recorded an issue at FocusTests.swift:30:9:
  Expectation failed: (engine.focusRollup(at: now(600)).duration(for: slack, on: today)
  → 600.0 seconds) == (.seconds(60) → 60.0 seconds)
✘ Test run with 1 test in 1 suite failed after 0.001 seconds with 1 issue.
```

Мёртвый процесс продолжил накапливать: 600 с вместо 60. Порядок возвращён, тест снова зелёный,
`git diff` этой перестановки не содержит.

### Дословные байты файла фокуса (критерий 17)

Получены прогоном `focusFileIsHandReadable` с временной печатью (печать убрана, `git diff`
файла тестов её не содержит):

```
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
```

Второй день записан из накопителя со значением 720,5 с — на диск ушло `720`, остаток остался в
памяти. Pretty-printed + `sortedKeys`, как у файла правил: строковая сортировка ключей вида
`2026-08-29` совпадает с хронологической.

### Лог фокуса (критерии 11 и 12)

Все восемь строк — `.notice`, логгер один, категория `focus`; вызовов `focusLog.debug/info/error`
нет:

```
Sources/TerminatorAppKit/FrontmostFocusObserver.swift:17:
  nonisolated let focusLog = Logger(subsystem: TerminatorLog.subsystem,
                                    category: TerminatorLog.Category.focus)
строка  88: интерполяций=3 privacy:.public=3   (frontmost changed)
строка 122: интерполяций=1 privacy:.public=1   (time zone changed)
строка 133: интерполяций=2 privacy:.public=2   (focus observation started)
строка 168: интерполяций=2 privacy:.public=2   (focus paused/resumed)
строка 192: интерполяций=1 privacy:.public=1   (day rollover)
WatchController 117: интерполяций=3 privacy:.public=3   (focus store loaded)
WatchController 232: интерполяций=3 privacy:.public=3   (focus written)
WatchController 235: интерполяций=2 privacy:.public=2   (focus flush failed)
```

Ни одного нового случая `Effect` — их по-прежнему три (`requestQuit`, `log`, `appFirstObserved`),
видов `LogEvent.Kind` по-прежнему шесть. `git status` по `EngineEffect.swift` и
`EngineLogRenderer.swift` — пусто, файлы не изменены.

### Sudden termination (критерий 13)

```
$ git diff -U0 -- Sources Tests | grep -nE 'NSSupportsSuddenTermination|disableSuddenTermination|enableSuddenTermination' || echo clean
clean
```

`Packaging/Info.plist` не изменён (`git status --short Packaging/` пусто). Док-комментарий в
`TerminatorApp.swift` объясняет запрет, **не называя** запрещённые идентификаторы дословно —
именно чтобы этот греп оставался честным.

### SuspendingClock (критерий 16)

```
Sources/TerminatorCore/AwakeInstant.swift:10:  /// - **suspending-семья** (`SuspendingClock`, ...
scripts/check-forbidden.sh:19:                #   - SuspendingClock в ПУТИ ДЕДЛАЙНА ...
```

Два вхождения, оба в комментариях; в коде тип не используется вовсе. Накопительное чтение —
`ProcessInfo.processInfo.systemUptime`, измеренный findings §9 член той же suspending-семьи:
`FrontmostFocusObserver.swift:28-30`. В пути дедлайна ни того, ни другого нет.

### Накопительный тип и точка постройки `Now` (критерий 10)

```swift
public struct AwakeInstant: Equatable, Hashable, Comparable, Sendable {
    public let sinceOrigin: Duration
    public init(sinceOrigin: Duration)
    public func advanced(by duration: Duration) -> AwakeInstant
    public func awakeSince(_ earlier: AwakeInstant) -> Duration
}
```

`Duration` и только он: ни `Date`, ни `TimeInterval` в типе нет, конверсии наружу нет.

`WatchController.swift` (бывшая строка 183) после правки:

```swift
    private var currentNow: Now {
        Now(wall: Date(), awake: currentAwakeInstant(), timeZone: .current)
    }

    private func dispatch(_ input: EngineInput) {
        perform(engine.handle(input, at: currentNow))
```

Конструкций `Now(` во всём дереве по-прежнему две плюс новый тестовый хелпер:
`WatchController.swift:262`, `WatchEngineTests.swift:582`, `FocusTests.swift:392`. Умолчаний у
полей нет, поэтому пропустить накопительное чтение нельзя — не соберётся.

### Четыре вставки (критерий 15)

`git diff -- Sources/TerminatorCore/WatchEngine.swift` содержит ровно четыре строки
`focus.endSpan(ofSession: key, in: sessions, config: config, at: now)`:

| Функция | Место |
|---|---|
| `applyConfig` | перед `sessions[key] = nil` в ветке «правила нет / выключено / дедлайн не считается» |
| `reconcile` | перед `guard let session = sessions.removeValue(forKey: key)` |
| `apply(_:pid:at:)` | перед `sessions[key] = nil` в случае `.notRunning` |
| `dropSessions` | перед `guard let session = sessions.removeValue(forKey: key)` |

Больше в этих функциях не изменено ничего, кроме сигнатуры `applyConfig` (см. «Отступления»).

### Дифф композиционного корня (критерий 14)

```diff
+    func applicationWillTerminate(_ notification: Notification) {
+        controller.flushFocus()
+    }
```

Плюс док-комментарий. Ничего не строится и никому не передаётся; проводка движка, хранилища и
наблюдателей осталась TASK-004.

## Acceptance criteria

| Критерий | Статус | Чем подтверждён |
|---|---|---|
| 1. `focusSpanIsFlushedBeforeProcessIsDropped` | выполнен | Тест зелёный; перестановка операций роняет его (вывод выше). Три соседних теста покрывают остальные пути: `spanIsFlushedWhenReconcileDropsTheSession`, `spanIsFlushedWhenQuitReportsTheProcessIsGone`, `spanIsFlushedWhenTheRuleIsDisabled` |
| 2. `spanAcrossMidnightSplitsIntoTwoDays` | выполнен | 600 + 600 = 1200 с ровно; проверяется и сумма, и каждая доля |
| 3. `eachPauseSignalClosesSpanAndItsResumeOpensANewOne` | выполнен | Параметризован по `FocusPauseReason.allCases`, `with 4 test cases passed`. Плюс `accrualResumesOnlyWhenTheLastPauseReasonClears` — доказательство, что причины держатся множеством |
| 4. `systemSleepAddsNoFocusSeconds` | выполнен | Стенные часы +8 ч при неподвижном `awake` → `.zero`; после пробуждения счёт идёт с нуля |
| 5. `nonRegularActivationDoesNotBreakTheSpan` | выполнен | 30 с одним спаном (разрыв дал бы 20); у `com.apple.UserNotificationCenter` записей нет |
| 6. `unwatchedAppClosesPreviousSpanAndPersistsNothing` | выполнен | 60 с у наблюдаемого, ноль записей у ненаблюдаемого, единственный ключ дня |
| 7. `persistedFocusIsVersionedIntegerSecondsWithoutTruncation` | выполнен | `schemaVersion == 1`; 1,5 с → `1`, ещё 1,5 с → `3` (а не `2`) |
| 8. `timeZoneChangeDoesNotRewriteRecordedDays` | выполнен | Записанный день переживает уход пояса на UTC−11. Вторая половина критерия — `dstDayOfTwentyFiveHoursIsCountedCorrectly`: 25 ч в 2026-11-01 и ноль в 2026-11-02 |
| 9. `flushPreservesDaysAlreadyOnDisk` | выполнен | День 2026-08-01 (3600) сохранён нетронутым; день из памяти дал 720+120=840 |
| 10. Накопительное чтение — отдельный тип без умолчания | выполнен | Объявление `AwakeInstant` и `WatchController.swift` выше |
| 11. Ни одного нового `Effect`, `LogEvent`/`EngineLogRenderer` не тронуты | выполнен | Список случаев и пустой `git status` по обоим файлам |
| 12. Каждая строка — `.notice`, категория `focus`, `privacy: .public` | выполнен | Таблица счёта интерполяций выше |
| 13. `Info.plist` не изменён, sudden termination в диффе нет | выполнен | `... || echo clean` → `clean` |
| 14. Изменение в `TerminatorApp.swift` — один хук | выполнен | Дифф выше |
| 15. По одной вставке в четырёх функциях удаления | выполнен | Дифф `WatchEngine.swift` выше |
| 16. `SuspendingClock` не в пути дедлайна | выполнен | Оба вхождения — комментарии; в коде тип не используется |
| 17. Дословные байты файла фокуса | выполнен, **ждёт утверждения схемы оркестратором** | Байты выше; имя `focus.json`, `schemaVersion: 1` |
| Ручной чеклист (7 пунктов) | **требует человека** | См. «Не запускалось» |

## Отступления и решения, которые должен утвердить оркестратор

Ни одно из трёх не выбрано молча — каждое названо здесь до приёмки.

### 1. Слив **прибавляет** накопленное этим запуском, а не замещает день целиком

Пакет говорит: «день из памяти замещает только сам себя, дни с диска, которых в памяти нет,
переносятся нетронутыми». Буквальное замещение корректно **только при засеянном движке**, а
движок стартует пустым. Перезапуск в полдень при буквальном замещении стёр бы всё утро того же
дня — та же потеря, что и «первый слив стирает историю», только на один день.

Засеять движок прочитанной свёрткой я не мог: такого шва нет ни в карточке, ни в амендменте 1,
ни в пакете (стоп-условие 1 запрещает его выдумывать). Поэтому слагаемое живёт в **писателе**,
то есть внутри разрешённой зоны:

- `FocusStore.load()` читает файл один раз и держит его как `recorded` (базу);
- `WatchEngine.focusRollup(at:)` отдаёт накопленное **этим запуском**;
- `FocusStore.flush(_:)` пишет `recorded.adding(accrued)`.

База не перечитывается между сливами — иначе каждый слив удваивал бы уже записанное. Дни,
которых этот запуск не касался, переносятся нетронутыми (критерий 9 зелёный). Если оркестратор
предпочтёт буквальное замещение, ему нужен шов засева движка — и это решение, а не правка.

### 2. `FrontmostApp` несёт четвёртое поле — `startTime: Date?`

Карточка перечисляет три поля (bundle id, pid, политика). Пакет требует: «Открытый спан хранит
**`SessionKey`**, а не голый pid. Слив при удалении срабатывает, когда ключ спана совпал с
удаляемым». `SessionKey` — это пара `(pid, p_starttime)`, поэтому без времени старта требование
пакета неисполнимо. Адаптер читает его тем же `launchAnchor(of:)`, что и наблюдатель процессов,
поэтому ключи сходятся байт в байт. Форма `SessionKey` и таблицы сессий не менялась.

### 3. `applyConfig` получил параметр `at now: Now`

Разрешена «одна вставка», но слив без момента времени не выражается, а `applyConfig` был
единственным из четырёх обработчиков без `now`. Изменены сигнатура и одна строка вызова в
`handle`. Семантика пересчёта дедлайнов не тронута: истечение здесь по-прежнему не оценивается.

### Мелкие швы, взятые как механически необходимые

- `WatchEngine.focusRollup(at:)` — read-only **функция**, а не свойство: свойство не знает
  времени и не смогло бы свернуть открытый спан, из-за чего каждый слив терял бы всё с момента
  последнего входа. Функция чистая, состояние движка не меняет, двойного счёта не даёт.
- `WatchController.currentNow` — приватное свойство, чтобы `flushFocus()` и `dispatch()` читали
  часы одинаково и точек постройки `Now` в дереве осталось ровно две.
- `WatchController.init` получил параметр `focusObserver` с умолчанием; `FocusStore` строится
  внутри от `store.dataDirectory` (композиционный корень ничего не передаёт, как и требует
  карточка).
- `WatchController.stop()` гасит новый таймер и наблюдатель.
- `FocusStore.flush` возвращает записанные байты (`@discardableResult`) — контроллеру нужен
  размер для лог-строки.

## API четырёх сигналов паузы

Пакет требует назвать их и пометить неизмеренные. **Ни один из этих API findings не мерили**,
кроме одного, поэтому все, кроме него, идут в ручной чеклист.

| Причина | Пауза | Возобновление | Измерено? |
|---|---|---|---|
| `.systemSleep` | `NSWorkspace.willSleepNotification` | `NSWorkspace.didWakeNotification` | **`didWakeNotification` — да** (findings §2: сработало и быстро). `willSleepNotification` — нет |
| `.displaySleep` | `NSWorkspace.screensDidSleepNotification` | `NSWorkspace.screensDidWakeNotification` | нет |
| `.screenLocked` | распределённое уведомление `com.apple.screenIsLocked` | `com.apple.screenIsUnlocked` | нет; **и Apple их не документирует** |
| `.sessionResignedActive` | `NSWorkspace.sessionDidResignActiveNotification` | `NSWorkspace.sessionDidBecomeActiveNotification` | нет; `sessionDidBecomeActiveNotification` уже используется в `WatchController.start()` с TASK-004, то есть прецедент в дереве есть, но замера нет |

Все шесть уведомлений `NSWorkspace` подписаны на `NSWorkspace.shared.notificationCenter`, пара
блокировки — на `DistributedNotificationCenter.default()`.

Отдельно и не менее важно: **KVO по `NSWorkspace.shared.frontmostApplication` findings тоже не
мерили.** Измерен KVO по `runningApplications` (§2). Карточка предписывает KVO именно здесь, и он
так и сделан, но если это свойство окажется не KVO-совместимым, вся сборка данных будет молчать,
и единственный, кто это заметит, — человек на пункте 2 чеклиста. Это главный неизмеренный риск
задачи.

## Не запускалось

**Ручной чеклист — семь пунктов, засчитать их я не могу.** Приложение не запускалось ни разу:
`./build.sh` бандл собирает, но не открывает, а запуск Terminator на живой машине начал бы
закрывать приложения пользователя по его настоящему конфигу.

Что должен проверить человек:

1. `./build.sh && open build/Terminator.app` — **никогда `swift run`** (findings §7).
2. Попереключаться между наблюдаемым и ненаблюдаемым приложением несколько раз. В логе должны
   появиться строки `frontmost changed:` с верными bundleID и политикой. **Это же проверка того,
   что KVO по `frontmostApplication` вообще срабатывает.**
3. Усыпить и разбудить дисплей, попереключаться снова. Ожидаются парные
   `focus paused: reason=display-sleep` / `focus resumed: reason=display-sleep`.
4. Заблокировать и разблокировать экран, сверив парные строки с `reason=screen-locked`. **Если
   пары нет — не сработали недокументированные имена распределённых уведомлений; это надо
   сообщить, а не чинить наугад.**
5. Переключить пользователя и вернуться, сверив пары с `reason=session-resigned-active`.
6. Выйти из приложения и посмотреть `~/Library/Application Support/com.svvoff.terminator/focus.json`:
   итоги правдоподобны, JSON читается руками, и в нём **только** наблюдаемые приложения.
7. Прочитать лог и убедиться, что ни одно интерполированное значение не показано как `<private>`:
   `log show --predicate 'subsystem == "com.svvoff.terminator"' --style compact --last 1h`
   (в оболочке автора `log` перехвачен — звать `/usr/bin/log`).

Дополнительно стоит проверить руками две вещи, которых юнит-тесты достать не могут: что за ночь
сна Mac фокус не вырос (сверить с ростом дедлайнов) и что `focus.json` не появляется в каталоге,
пока ни одно наблюдаемое приложение не побывало фронтмост.

**Не проверялось автоматически** также: адаптерный слой целиком — юнит-тесты для него запрещены
не-целью карточки (никаких мок-`NSWorkspace`).

## Проверка скоупа

```
 M Sources/Terminator/TerminatorApp.swift
 M Sources/TerminatorAppKit/WatchController.swift
 M Sources/TerminatorCore/EngineInput.swift
 M Sources/TerminatorCore/Now.swift
 M Sources/TerminatorCore/WatchEngine.swift
 M Tests/TerminatorCoreTests/WatchEngineTests.swift
?? Sources/TerminatorAppKit/FrontmostFocusObserver.swift
?? Sources/TerminatorCore/AwakeInstant.swift
?? Sources/TerminatorCore/FocusFormat.swift
?? Sources/TerminatorCore/FocusInputs.swift
?? Sources/TerminatorCore/FocusLedger.swift
?? Sources/TerminatorCore/FocusRollup.swift
?? Sources/TerminatorCore/FocusStore.swift
?? Tests/TerminatorCoreTests/FocusTests.swift
```

`git diff --stat -- Sources Tests` → 6 файлов, 209 вставок, 13 удалений, плюс восемь новых.

Запрещённые зоны — не тронуты:

- `Packaging/Info.plist`, `build.sh`, `Package.swift`, подпись, keychain — без изменений
  (`git status` по ним пуст);
- `QuitSender.swift`, `EngineLogRenderer.swift`, `EngineEffect.swift`, `ProcessSession.swift`,
  `ProcessLaunchTime.swift` — без изменений; путь quit, код Apple Events, расчёт дедлайна и
  стратегия истечения не тронуты;
- `PopoverView.swift`, `PopoverModel.swift`, `PopoverViewModel.swift` и их тесты — без изменений;
  швы TASK-006 в контроллере (`activeSessions`, `config`, `quarantine`, `apply(_:)`,
  `onStateChanged`, `reloadFromDisk()`) не переписаны, только соседствуют с новыми;
- `LoginItemService.swift`, `LoginItem.swift` и их тесты — без изменений;
- `UserDefaults`, `Bundle.module`, `swift run`, `swiftLanguageMode(.v5)`, `@preconcurrency`,
  `@unchecked Sendable` — не добавлены (`check-forbidden.sh` EXIT=0);
- файлы хендоффа соседних потоков (`*-popover.md`, `*-loginitem.md`, `current-task-packet.md`,
  `current-execution-report.md`) и карточки TASK-006/TASK-008 не читались и не правились;
- `macos-findings.md` не правился: ни одно измерение карточке не противоречило;
- в настоящий `~/Library/Application Support/com.svvoff.terminator/` за всё исполнение не
  записано ничего — там по-прежнему только `config.json` от 18:05 (не моя запись), файла
  `focus.json` нет; в `~/Library/LaunchAgents/` я не заходил.

## Риски

1. **KVO по `frontmostApplication` не измерен.** Если свойство не KVO-совместимо, сбор молча
   даст ноль. Ловится только пунктом 2 чеклиста. Самый крупный остаточный риск.
2. **Имена уведомлений блокировки экрана недокументированы** (`com.apple.screenIsLocked` /
   `com.apple.screenIsUnlocked`). Если они не приходят, экран под замком будет считаться
   фокусом — числа поедут вверх, а симптома не будет. Пункт 4 чеклиста.
3. **Спан приложения без прочитанного `p_starttime` не закрывается удалением сессии** (ключа у
   него нет). Закроется ближайшей сменой фронтмоста. Перебор ограничен и редок: `p_starttime`
   вернулся для 90 из 90 процессов (findings §3).
4. **Правило выключили для приложения без записи в таблице сессий** — накопление идёт до
   ближайшего входа фокуса, на котором спан закрывается (проверка «правило ещё включено» стоит
   в начислении). Для обычного случая — приложения с сессией — спан закрывается ровно в момент
   правки, это покрыто тестом.
5. **До 60 с накопления теряется при аварийном завершении** Terminator (без
   `applicationWillTerminate`). Штатный выход, логаут, перезагрузка и выключение покрыты.
6. **Усечение до целых секунд на диске**: дневной итог в файле может быть на долю секунды ниже
   памяти. Остаток не теряется, он просто ещё не набрался до целой секунды.
7. **`TimeZone.current` снимается на каждый вход**, а не подписан на изменение. Смена пояса
   дополнительно шлёт `.dayRollover`, так что расхождение живёт максимум до ближайшего входа.
8. **Пропорциональное расщепление по полуночи** — оценка: реальное распределение бодрствования
   внутри интервала неизвестно. Сумма долей точна, ошибка возможна только в дележе между двумя
   днями и только если внутри интервала машина спала неравномерно относительно полуночи.

## Незавершённое и follow-up

- **Утверждение схемы файла** (`focus.json`, `schemaVersion: 1`, форма выше) — за оркестратором.
  С момента приёмки смена формата = миграция.
- **Запись схемы и имени файла в журнал исполнения** — требование раздела Documentation updates
  карточки; журнал (`docs/ai/execution-log/latest.md`) правит оркестратор, я в `docs/` ничего не
  трогал.
- **Ручной чеклист** — семь пунктов выше.
- Кандидат в отдельную карточку (решает оркестратор): один из двух неизмеренных механизмов —
  KVO по `frontmostApplication` и распределённые уведомления блокировки — стоит после ручной
  проверки занести в `macos-findings.md` новой секцией, чтобы следующая задача не гадала.
