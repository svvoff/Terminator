# Отчёт об исполнении

## Задача

**TASK-004 — Watch engine. Раунд 2** (после REQUEST_CHANGES по итогам ручного чеклиста).

Задание — амендмент 3 карточки `docs/product/backlog/tasks/in-progress/TASK-004-watch-engine.md`.
Секция «4. Launch time» той же карточки читалась как заведомо отменённая амендментом.

## Кратко

Из `launchAnchor(of:)` удалён откат на `launchDate`: нет `p_starttime` — нет якоря, возвращается
nil. Вместе с откатом ушла лог-строка `launch time degraded to launchDate`. Половина функции про
сверку `launchDate` не менялась. Добавлен один юнит-тест редьюсера — критерий 25.
`WatchEngine` и остальные девять файлов ядра и адаптеров не тронуты.

Тестов было 44, стало 45.

## Изменённые файлы

| Файл | Что изменено |
|---|---|
| `Sources/TerminatorAppKit/ProcessLaunchTime.swift` | `launchAnchor(of:)`: трёхстрочное тело `guard` заменено на `return nil`; удалена строка `engineLog.notice("launch time degraded to launchDate: …")`; док-комментарий переписан с трёх исходов на два и объясняет, почему откат не просто недостижим, а вреден |
| `Tests/TerminatorCoreTests/WatchEngineTests.swift` | добавлен `deadProcessStillListedDoesNotResurrectSession()` (критерий 25); в док-комментарии `@Suite` диапазон «пункты 1–22» стал «пункты 1–22 и 25» |

Больше ничего в дереве не менялось — ни исходников, ни тестов, ни `Package.swift`, ни доков,
ни `build.sh`, ни скриптов.

### Одна правка вне буквы «добавление одного теста» — раскрываю явно

В `WatchEngineTests.swift` изменена **одна строка комментария**: заголовок сюиты говорил
«Критерии приёмки TASK-004, пункты 1–22», а файл теперь покрывает ещё и 25-й. Ни один
существующий тест не тронут: 22 из 23 тел `@Test` побайтово прежние. Если оркестратор считает
это выходом за скоуп — строка откатывается одним движением, но тогда заголовок файла остаётся
неверным.

## Изменения поведения

**Было.** `p_starttime` недоступен → берётся `launchDate` (если он есть), пишется
`launch time degraded to launchDate`, процесс принимается движком с якорем `launchDate`.

**Стало.** `p_starttime` недоступен → `launchAnchor` возвращает nil → `ObservedProcess.startTime`
равен nil → движок процесс **не принимает** и переоценивает на следующей сверке (это уже
существующее поведение редьюсера, критерий 15, тест
`processWithoutLaunchTimeDoesNotStartCountdown`).

Что это чинит по трассе из пакета: в окне «процесс мёртв, но ещё в снимке
`NSWorkspace.runningApplications`» (findings §4 — отставание до 19 с) откат подставлял
`launchDate`, отличающийся от `p_starttime` на 8 мс. Ключ сессии `(pid, p_starttime)` расходился,
и движок снимал настоящую сессию ложным `app-exited`, чтобы завести фантомную и сразу
просроченную. Теперь в этом окне сверка делает ровно одно: снимает сессию, потому что пары
`(pid, startTime)` в снимке нет, и ничего не заводит взамен.

`WatchEngine` не менялся сознательно: на данных, которые ему давал адаптер, он вёл себя
правильно. Дефект был в адаптере, сообщавшем время старта мёртвого процесса.

## Доказательства валидации

Перед прогоном `.build` удалён целиком, чтобы вывод компилятора был настоящим, а не кэшем.

| Команда | Результат | Вывод |
|---|---|---|
| `swift build` | EXIT=0, `warning:` — 0 строк | см. ниже |
| `swift build -c release` | EXIT=0, `warning:` — 0 строк | см. ниже |
| `swift test` | EXIT=0, **45 тестов**, `warning:` — 0 строк | см. ниже |
| `swift test -c release` | EXIT=0, **45 тестов**, `warning:` — 0 строк | см. ниже |
| `scripts/check-forbidden.sh` | EXIT=0 | `OK:    запрещённых конструкций не найдено` |
| `./build.sh` | EXIT=0, терминальный шаг `codesign --verify --strict` молчит | см. ниже |

### `swift build`

```
$ rm -rf .build && swift build
Building for debugging...
[0/8] Write sources
[3/8] Write Terminator-entitlement.plist
[4/8] Write swift-version--58304C5D6DBC2206.txt
[6/23] Compiling TerminatorCore ObservedProcess.swift
...
[27/31] Compiling TerminatorAppKit ProcessLaunchTime.swift
[28/31] Emitting module TerminatorAppKit
[29/34] Emitting module Terminator
[30/34] Compiling Terminator TerminatorApp.swift
[31/34] Compiling Terminator PlaceholderView.swift
[32/34] Linking Terminator
[33/34] Applying Terminator
Build complete! (9.31s)
EXIT=0
grep -c 'warning:' → 0
```

### `swift build -c release`

```
$ swift build -c release
Building for production...
[0/6] Write sources
[3/6] Write swift-version--58304C5D6DBC2206.txt
[5/7] Compiling TerminatorCore ConfigFormat.swift
[6/8] Compiling TerminatorAppKit EngineLogRenderer.swift
[7/9] Compiling Terminator PlaceholderView.swift
[8/9] Linking Terminator
Build complete! (6.78s)
EXIT=0
grep -c 'warning:' → 0
```

### `swift test`

```
$ swift test
Test Suite 'All tests' passed at 2026-08-28 09:22:18.514.
◇ Test deadProcessStillListedDoesNotResurrectSession() started.
✔ Test deadProcessStillListedDoesNotResurrectSession() passed after 0.029 seconds.
✔ Suite "Доменная модель правила" passed after 0.030 seconds.
✔ Suite "Движок наблюдения" passed after 0.030 seconds.
✔ Suite "Формат конфига на диске" passed after 0.062 seconds.
✔ Suite "Хранилище конфига: карантин, уборка, путь" passed after 0.062 seconds.
✔ Suite "Долговечная запись" passed after 0.074 seconds.
✔ Test run with 45 tests in 5 suites passed after 0.074 seconds.
EXIT=0
grep -c 'warning:' → 0
```

### `swift test -c release`

```
$ swift test -c release
◇ Test deadProcessStillListedDoesNotResurrectSession() started.
✔ Test deadProcessStillListedDoesNotResurrectSession() passed after 0.036 seconds.
✔ Suite "Движок наблюдения" passed after 0.039 seconds.
✔ Suite "Доменная модель правила" passed after 0.051 seconds.
✔ Suite "Формат конфига на диске" passed after 0.069 seconds.
✔ Suite "Хранилище конфига: карантин, уборка, путь" passed after 0.077 seconds.
✔ Suite "Долговечная запись" passed after 0.090 seconds.
✔ Test run with 45 tests in 5 suites passed after 0.090 seconds.
EXIT=0
grep -c 'warning:' → 0
```

### Счёт тестов: 44 → 45, ровно один новый

Базовый прогон **до** правки, на том же дереве:

```
$ swift test
✔ Test run with 45 tests in 5 suites passed  ← после
✔ Test run with 44 tests in 5 suites passed  ← до (снято перед началом работы)
```

`grep -c "@Test func" Tests/TerminatorCoreTests/WatchEngineTests.swift` → **23** (было 22).
Ни один из 44 прежних тестов не падал ни в одном из четырёх прогонов и ни один не правился.

### `scripts/check-forbidden.sh`

```
$ scripts/check-forbidden.sh
OK:    запрещённых конструкций не найдено
EXIT=0
```

### `./build.sh`

```
$ ./build.sh
--- swift build -c debug ---
Building for debugging...
Build complete! (0.14s)
--- assemble build/Terminator.app ---
--- codesign --force --sign "Terminator Dev" (последняя мутация бандла) ---
build/Terminator.app: replacing existing signature
--- designated requirement guard ---
designated requirement: identifier "com.svvoff.terminator" and certificate leaf = H"74d582911cd0b2c7ff3961af4bb0561efd6a8f24"
--- codesign --verify --strict (терминальный шаг) ---
EXIT=0
```

Подпись — `Terminator Dev`, ad-hoc не использовался, порядок шагов в `build.sh` не менялся.

## Acceptance criteria

| Критерий | Статус | Чем подтверждён |
|---|---|---|
| Амендмент 3, п. 1: `launchAnchor(of:)` не откатывается на `launchDate` | выполнен | дифф: тело `guard` — `return nil`; `grep -rn "degraded" Sources Tests scripts build.sh` → пусто |
| Амендмент 3, п. 2: `launchDate` остаётся сверкой, `p_starttime` побеждает при расхождении > 0.4 с | выполнен | дифф: блок `if let launchDate { … disagreement > 0.4 … }` не изменён ни на символ |
| Амендмент 3, п. 2: лог-строка `launch time degraded to launchDate` удалена | выполнен | `grep -rn "degraded" Sources Tests scripts build.sh` → ничего |
| **Критерий 25** `deadProcessStillListedDoesNotResurrectSession` | выполнен | тест зелёный в debug и release; сессия снимается ровно одним `app-exited` (`sweep.logKinds == [.appExited]`), `activeSessions` пуст, `quitRequests` пуст на сверке и на всех тиках до +600 с |
| Критерий 15 (не менялся, теперь покрывает всю историю) | выполнен | `processWithoutLaunchTimeDoesNotStartCountdown` зелёный без правок |
| Критерии 1–22 раунда 1 | выполнены | 22 теста сюиты «Движок наблюдения» зелёные без единой правки |
| Ручной чеклист | **требует человека** | см. «Не запускалось» |

### Как именно критерий 25 проверяется тестом

Сессия заводится на `p_starttime` (`pid 501`, старт `t(-600)`, лимит 10 мин) и доводится до
`.awaitingQuit` тиком на дедлайне — то же состояние, что в трассе с машины автора. Затем
приходит `.reconcile`, в снимке которого тот же `pid 501`, тот же bundle id, `.regular`, но
`startTime == nil`. Проверяется:

- `sweep.logKinds == [.appExited]` — ровно одно событие, не два и не три;
- `sweep.quitRequests.isEmpty` — второго `quit-requested` нет;
- `engine.activeSessions.isEmpty` — фантомная сессия не заведена;
- цикл до +600 с: повторные сверки с тем же снимком возвращают пустой массив эффектов, тики
  не эмитят `.requestQuit`, `activeSessions` остаётся пустым.

## Не запускалось

- **Ручной чеклист (`validation_profile: [manual-checklist]`) — не засчитан и засчитан быть не
  может.** Человеку нужно перезапустить испытание 1 на исправленной сборке
  (`./build.sh && ./build/Terminator.app/Contents/MacOS/Terminator`), закрыть наблюдаемое
  приложение по дедлайну и убедиться в логе, что:
  строки `launch time degraded to launchDate` нет вовсе; одно закрытие даёт **один**
  `quit-requested` и **один** `app-exited`; строки `countdown-started` на якоре, отличающемся от
  `p_starttime`, не появляется.
- **Против живых приложений ничего не запускалось.** Ни одного Apple Event, ни одного quit,
  собранное приложение не запускалось. `./build.sh` только собирает и подписывает.
- **Адаптер юнит-тестами не покрыт и покрыт быть не может** в этой форме: `launchAnchor(of:)`
  принимает `NSRunningApplication`, который нельзя сконструировать в тесте. Отсюда честная
  оговорка: новый тест — это **фиксация контракта редьюсера**, а не red-green доказательство
  правки адаптера. До правки он тоже был бы зелёным, потому что редьюсер не менялся. Он ловит
  будущую регрессию в движке; правку адаптера подтверждает только ручной чеклист.

## Проверка скоупа

Затронуты ровно две разрешённые зоны:

```
Sources/TerminatorAppKit/ProcessLaunchTime.swift   (функция launchAnchor(of:) и её док-комментарий)
Tests/TerminatorCoreTests/WatchEngineTests.swift   (один добавленный тест + одна строка док-комментария сюиты)
```

Не тронуты, как требуют не-цели: `WatchEngine.swift`, `EngineInput.swift`, `EngineEffect.swift`,
`ProcessSession.swift`, `QuitOutcome.swift`, `ExpiryAction.swift`, `Now.swift`,
`ObservedProcess.swift`, `QuitSender.swift`, `RunningApplicationsObserver.swift`,
`WatchController.swift`, `EngineLogRenderer.swift`, `TerminatorApp.swift`, `Package.swift`.
Ни один из 22 существующих тестов не изменён. Карточки решений, findings, бэклог и статусы задач
не трогались.

`git status --short` после правки — побайтово тот же список, что и до неё (оба изменённых файла
уже были untracked с раунда 1, новых файлов не появилось):

```
 M Sources/Terminator/TerminatorApp.swift
 M docs/ai/current-context.md
 M docs/ai/execution-state.md
 M docs/ai/handoff/current-execution-report.md
 M docs/ai/handoff/current-task-packet.md
RM docs/product/backlog/tasks/ready/TASK-004-watch-engine.md -> docs/product/backlog/tasks/in-progress/TASK-004-watch-engine.md
 M docs/product/decisions/active/DEC-002-expiry-action.md
?? Sources/TerminatorAppKit/EngineLogRenderer.swift
?? Sources/TerminatorAppKit/ProcessLaunchTime.swift
?? Sources/TerminatorAppKit/QuitSender.swift
?? Sources/TerminatorAppKit/RunningApplicationsObserver.swift
?? Sources/TerminatorAppKit/WatchController.swift
?? Sources/TerminatorCore/EngineEffect.swift
?? Sources/TerminatorCore/EngineInput.swift
?? Sources/TerminatorCore/ExpiryAction.swift
?? Sources/TerminatorCore/Now.swift
?? Sources/TerminatorCore/ObservedProcess.swift
?? Sources/TerminatorCore/ProcessSession.swift
?? Sources/TerminatorCore/QuitOutcome.swift
?? Sources/TerminatorCore/WatchEngine.swift
?? Tests/TerminatorCoreTests/WatchEngineTests.swift
```

(`docs/ai/handoff/current-execution-report.md` в списке — это сам этот файл.)

## Риски

1. **Процесс без `p_starttime` теперь не считается вообще.** Если найдётся живой процесс, у
   которого `sysctl(KERN_PROC_PID)` молчит, его отсчёт не начнётся никогда, а не начнётся от
   `launchDate`. findings §3 измерил 90 из 90 у живых, так что состояние считается
   несуществующим — но это измерение, а не гарантия ядра. Симптом, если оно всё-таки
   существует: приложение видно в логе как `app-detected`, а `countdown-started` для него не
   появляется никогда. Это заметно в логе и не тихо.
2. **Окно всё ещё существует, просто теперь молчит.** Мёртвый процесс, висящий в снимке до
   19 с, снимается первой же сверкой. Если он в этом окне действительно перезапустится с тем же
   pid, новая сессия заведётся на следующей сверке, когда `p_starttime` станет доступен, —
   с полным свежим лимитом, как требует DEC-003.
3. **Правка проверена только тестами и глазами.** Подтверждение, что фантом на живой машине
   исчез, даст только испытание 1 ручного чеклиста.

## Незавершённое и follow-up

- Испытание 1 ручного чеклиста на исправленной сборке — за человеком.
- Секция «4. Launch time» карточки TASK-004 по-прежнему описывает удалённый откат. Амендмент 3
  это оговаривает явно, но привести секцию в соответствие (или оставить как есть, раз амендмент
  сильнее) — решение оркестратора; исполнитель карточки не правит.
- Свою работу не принимаю: продакшн-код ревьюит оркестратор отдельным ходом.
