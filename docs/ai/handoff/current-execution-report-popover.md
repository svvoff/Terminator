# Отчёт об исполнении

## Задача

TASK-006 — Menu bar popover: список приложений, добавление и удаление, лимит, переключатель,
живой обратный отсчёт. Пакет: `docs/ai/handoff/current-task-packet-popover.md`.

## Кратко

Вью-модель поповера написана в `TerminatorCore` как чистая функция от конфига, живых сессий,
состояния карантина и `now`; там же 14 именованных тестов, все зелёные. В `WatchController`
добавлены пять швов (шестой — в `TerminatorApp.swift`), все — добавления: ни редьюсер, ни
арифметика дедлайнов, ни каденции, ни `perform`, ни `QuitSender`, ни сборка графа не тронуты.
Плейсхолдерное вью заменено настоящим поповером: список правил, `NSOpenPanel`-добавление,
удаление без подтверждения, редактор лимита, переключатель, живой отсчёт через
`TimelineView(.periodic)`, баннер карантина и кнопка «Quit Terminator».

Приложение **не запускалось**: на машине уже висит процесс прошлой сборки (pid 76503, старт
06:18:32), а остановить его можно только кнопкой в поповере — сигналы запрещены. Весь
`manual-checklist` (12 пунктов) остаётся человеку и перечислен ниже.

## Изменённые файлы

| Файл | Что изменено |
|---|---|
| `Sources/TerminatorCore/PopoverViewModel.swift` | **новый.** Вью-модель: `PopoverViewModel` (строки, баннер, `isEmpty`), `PopoverRow`, `PopoverInstance`, `PopoverInstanceStatus`, `PopoverRefusal`, `PopoverBanner`, `LimitEditorOutcome`, формат остатка, порядок строк, валидатор лимита, предикат красных глаз, `RuleRejectionReason.editorMessage`. Только Foundation. |
| `Tests/TerminatorCoreTests/PopoverViewModelTests.swift` | **новый.** Сьюта «Вью-модель поповера»: 14 именованных тестов из критерия 2. |
| `Sources/TerminatorAppKit/WatchController.swift` | швы 1–5: `activeSessions`, `config`, `quarantine`, `apply(_:)`, `onStateChanged`, `reloadFromDisk()`. Только добавления. |
| `Sources/Terminator/TerminatorApp.swift` | шов 6: `private let controller` → `let controller`, одно хранимое свойство `popover`, одно присваивание `onStateChanged` в `applicationDidFinishLaunching`; `@State glyphEyes` уехал вместе с плейсхолдером; вью заменено на `PopoverView`. |
| `Sources/Terminator/PopoverModel.swift` | **новый.** `@Observable` модель поповера, живущая в `AppDelegate`: снимок состояния, бит глаз, строка обратной связи, действия (добавить, удалить, лимит, переключатель), логирование под категорией `store`. |
| `Sources/Terminator/PopoverView.swift` | **новый.** SwiftUI-поповер: `TimelineView(.periodic)`, строка правила, статусы экземпляров, баннер карантина, кнопки Add/Quit. |
| `Sources/Terminator/PlaceholderView.swift` | **удалён** — это и есть «замена плейсхолдерного вью». Кнопка «Quit Terminator» перенесена в `PopoverView`. |

`Package.swift` не изменён. `LoginItemService` в диффе не упоминается.

## Изменения поведения

- Клик по черепу открывает поповер (`.menuBarExtraStyle(.window)`, как и было). При каждом
  открытии зовётся `controller.reloadFromDisk()`: `store.load()` → `.configChanged` →
  `reconcile()`. Файл при этом **только читается** — ни починки, ни миграции, ни перезаписи.
- Правки конфига идут **только** через `controller.apply(_:)`: запись через хранилище, затем
  `.configChanged(store.config)`, затем `reconcile()` — и последние два шага только при
  успешной записи. Прямых вызовов `ConfigStore.save(_:)` из UI нет.
- Остаток пересчитывается от абсолютного `Date`-дедлайна на каждый рендер; `now` подаёт
  `TimelineView(.periodic(from: .now, by: 1))`. Своего `Timer` во вью нет, ассертов активности
  нет, хранимого счётчика нет.
- Глаза глифа: `.active`, если есть сессия в фазе `.counting` или `.awaitingQuit`; терминальная
  `.refused` их не зажигает. Бит считается в `PopoverModel.refresh()`, которую дёргает
  `controller.onStateChanged` на каждом входе движка, то есть и при закрытом поповере.
- Новое правило создаётся **включённым** (`enabledAt = Date()`) с лимитом 60 минут по
  умолчанию (`PopoverModel.defaultLimitMinutes`). Карточка и пакет умалчивают об обоих
  значениях — см. «Риски».
- Строка обратной связи (`notice`) **не** сбрасывается при открытии поповера, только в начале
  следующего действия пользователя. Это сознательно: если `NSOpenPanel` закрывает поповер
  (оговорка пакета, не проверена), отказ «у бандла нет идентификатора» иначе было бы негде
  показать.
- Повторное добавление уже добавленного приложения не перезаписывает правило, а даёт строку
  «is already on the list» — иначе `set(_:)` переякорил бы дедлайн незаметно для пользователя.

## Доказательства валидации

| Команда | Результат | Вывод |
|---|---|---|
| `swift build` (после `rm -rf .build`) | OK, **ноль** `warning:` | см. ниже |
| `swift test` | 64 теста в 7 сьютах, все зелёные (было 50) | см. ниже |
| `swift test --filter PopoverViewModelTests` | 14 тестов, все зелёные | см. ниже |
| `scripts/check-forbidden.sh` | OK | `OK:    запрещённых конструкций не найдено` |
| `./build.sh` | exit 0, терминальный шаг `codesign --verify --strict` прошёл | см. ниже |

### `swift build` — чистая сборка с нуля

```
$ rm -rf .build && swift build
[20/26] Compiling TerminatorCore ConfigStore.swift
[21/26] Compiling TerminatorCore PopoverViewModel.swift
[22/26] Emitting module TerminatorCore
[23/26] Compiling TerminatorCore WatchEngine.swift
[24/34] Compiling TerminatorAppKit RunningApplicationsObserver.swift
[25/34] Compiling TerminatorAppKit WatchController.swift
...
[32/38] Emitting module Terminator
[33/38] Compiling Terminator PopoverModel.swift
[34/38] Compiling Terminator TerminatorApp.swift
[35/38] Compiling Terminator PopoverView.swift
[36/38] Linking Terminator
[37/38] Applying Terminator
Build complete! (7.58s)

$ swift build 2>&1 | grep -c "warning:"
0
$ swift build --build-tests 2>&1 | grep -i "warning:"
(пусто)
```

### `swift test`

```
$ swift test 2>&1 | tail -6
✔ Test startupSweepRemovesStrayTempFiles() passed after 0.047 seconds.
✔ Test limitOutsideOneToFourHundredEightyMinutesIsRejected() passed after 0.055 seconds.
✔ Suite "Хранилище конфига: карантин, уборка, путь" passed after 0.055 seconds.
✔ Test durableWriteLeavesNoTempFilesBehind() passed after 0.071 seconds.
✔ Suite "Долговечная запись" passed after 0.071 seconds.
✔ Test run with 64 tests in 7 suites passed after 0.071 seconds.
```

Именованные тесты критерия 2 — все четырнадцать:

```
$ swift test --filter PopoverViewModelTests
✔ Test remainingTimeAtOrAboveOneHourFormatsAsHoursMinutesSeconds() passed after 0.001 seconds.
✔ Test remainingTimeUnderOneHourFormatsAsMinutesAndSeconds() passed after 0.001 seconds.
✔ Test refusedSessionDoesNotKeepEyesRed() passed after 0.001 seconds.
✔ Test limitEditorRejectsValuesOutsideOneToFourHundredEightyMinutes() passed after 0.001 seconds.
✔ Test rulesWithNoRunningInstanceSortAfterRunningOnes() passed after 0.001 seconds.
✔ Test emptyStateIsProducedForZeroRules() passed after 0.001 seconds.
✔ Test rowsSortAscendingByRemainingTime() passed after 0.001 seconds.
✔ Test remainingTimeIsComputedFromSuppliedNow() passed after 0.001 seconds.
✔ Test refusedSessionIsDistinguishableFromCounting() passed after 0.001 seconds.
✔ Test disabledRulesSortLast() passed after 0.001 seconds.
✔ Test ruleWithTwoRunningInstancesYieldsTwoRemainingTimes() passed after 0.001 seconds.
✔ Test equalRemainingTimesBreakTieByBundleIdentifier() passed after 0.001 seconds.
✔ Test deadlineAlreadyPastFormatsAsZero() passed after 0.001 seconds.
✔ Test quarantinedStoreProducesTheReadOnlyBanner() passed after 0.002 seconds.
✔ Test run with 14 tests in 1 suite passed after 0.002 seconds.
```

### `scripts/check-forbidden.sh`

```
$ scripts/check-forbidden.sh
OK:    запрещённых конструкций не найдено
```

### `./build.sh`

```
$ ./build.sh
--- swift build -c debug ---
Build complete! (0.14s)
--- assemble build/Terminator.app ---
--- codesign --force --sign "Terminator Dev" (последняя мутация бандла) ---
build/Terminator.app: replacing existing signature
--- designated requirement guard ---
designated requirement: identifier "com.svvoff.terminator" and certificate leaf = H"74d582911cd0b2c7ff3961af4bb0561efd6a8f24"
--- codesign --verify --strict (терминальный шаг) ---
=== build.sh exit: 0 ===
```

### Механические проверки критериев

```
$ grep -rn "openSettings\|Settings(" Sources/
Sources/Terminator/PopoverView.swift:7:/// окна настроек нет: сцена `Settings` выброшена из скоупа, потому что `openSettings` на
        (единственное вхождение — комментарий; сцены Settings и вызова openSettings нет)

$ grep -rn "menuBarExtraStyle\|\.menu\b" Sources/
Sources/Terminator/TerminatorApp.swift:40:        .menuBarExtraStyle(.window)

$ grep -rn "\.save(" Sources/Terminator Sources/TerminatorAppKit
Sources/TerminatorAppKit/WatchController.swift:148:        try store.save(config)
        (единственный вызов — внутри шва apply(_:); из UI прямых вызовов нет)

$ grep -rn "LoginItemService" Sources/Terminator Sources/TerminatorAppKit/WatchController.swift
        (пусто)
```

## Acceptance criteria

| Критерий | Статус | Чем подтверждён |
|---|---|---|
| 1. Вью-модель в `TerminatorCore`, тесты там же, без AppKit, без меню-бара, без `sleep` | выполнен | `Sources/TerminatorCore/PopoverViewModel.swift` — только `import Foundation`; `check-forbidden.sh` гейтит `import AppKit` в ядре; тесты синхронные, без sleep, файловая система только через `withTemporaryDirectory` |
| 2. Четырнадцать именованных тестов существуют и зелёные | выполнен | вывод `swift test --filter PopoverViewModelTests` выше, 14 из 14 |
| 3. Вью-модель выставляет read-only состояние хранилища; баннер — функция этого состояния | выполнен | `PopoverViewModel.banner = quarantine.map(PopoverBanner.init)`; вью только рисует. Тест `quarantinedStoreProducesTheReadOnlyBanner` доводит **настоящий** `ConfigStore` до карантина битым файлом и проверяет, что `save` после этого бросает |
| 4. Нет сцены `Settings` и вызова `openSettings` | выполнен | грep выше |
| 5. `.menuBarExtraStyle(.window)`; `.menu` не встречается | выполнен | грep выше; `TerminatorApp.swift:40` не менялся |
| 6. Красные глаза — функция фаз, выведенная из движка; модель живёт вне поповера | выполнен (код) / требует человека (наблюдение) | `PopoverViewModel.anyCountdownInFlight(in:)` + тест `refusedSessionDoesNotKeepEyesRed`; бит считает `PopoverModel.refresh()`, модель держит `AppDelegate` (`private(set) lazy var popover`), не вью. Что глиф в баре реально перерисовывается — пункт 10 чеклиста |
| 7. `onStateChanged` присваивается ровно один раз в `applicationDidFinishLaunching`; сборка графа не изменена | выполнен | дифф `TerminatorApp.swift` ниже: одна строка присваивания; `WatchController(store: ConfigStore())` тот же, только `private` снято по шву 6 |
| 8. Поповер зовёт `reloadFromDisk()` при открытии | выполнен (код) / требует человека (что `.onAppear` срабатывает на каждое открытие) | `PopoverView.body` → `.onAppear { model.popoverDidOpen() }` → `controller.reloadFromDisk()`. Пункт 14 чеклиста измеряет это на живом приложении |
| 9. `apply(_:)` делает три вещи по порядку; прямых `save(_:)` из UI нет | выполнен | `WatchController.apply(_:)`: `try store.save` → `dispatch(.configChanged(store.config))` → `reconcile()`; грep по `.save(` выше |
| 10. Кнопка «Quit Terminator» есть, в том числе в пустом состоянии | выполнен | `PopoverView.content(_:)` — кнопка вне ветки `isEmpty`, в нижней строке рядом с «Add App…» |
| 11. Путь добавления зовёт `Bundle(url:)` и не создаёт правила при `nil`; отказ виден строкой | выполнен (код) / требует человека (видимость) | `PopoverModel.addApplication()`: `guard let bundleIdentifier = Bundle(url: url)?.bundleIdentifier else { notice = …; log; return }` — до всякого построения `Rule`. Пункт 5 чеклиста |
| 12. Ни один `OSStatus` не показывается и ни во что не отображается; ветвление по `QuitRefusal` сделано | выполнен | `PopoverInstanceStatus.init(_ phase:)` ветвится на `.attemptsExhausted` и `.status`, значение из второго не проносится. Тест `refusedSessionIsDistinguishableFromCounting` проверяет, что `-1743` и `-600` дают **одно и то же** значение `.refused(.systemRefused)` |
| 13. Каждая интерполяция в лог-строках несёт `privacy: .public`, подсистема — общая константа | выполнен | три лог-строки в `PopoverModel.swift`, все интерполяции с `privacy: .public`; логгер собран из `TerminatorLog.subsystem` и `TerminatorLog.Category.store`, новых категорий нет |
| 14. Шесть швов ровно в объявленном виде; редьюсер и прочее не изменены | выполнен | дифф обоих файлов ниже: в `WatchController` только вставки, `reconcile()`, `stop()`, `perform` и `start()` не тронуты |
| 15. `LoginItemService` в диффе не упоминается; `Package.swift` не изменён | выполнен | грep выше; `Package.swift` отсутствует в `git status` |

### Дифф `WatchController.swift` (швы 1–5)

```diff
@@ -38,6 +38,28 @@ public final class WatchController {
     /// Каденция полной сверки.
     public static let sweepInterval: TimeInterval = 30
 
+    public var onStateChanged: (() -> Void)?
+
+    public var activeSessions: [ProcessSession] { engine.activeSessions }
+
+    public var config: RuleConfig { store.config }
+
+    public var quarantine: ConfigLoadFailure? { store.quarantine }
+
     public init(
@@ -107,6 +129,42 @@ public final class WatchController {
         dispatch(.reconcile(observed: NSWorkspace.shared.runningApplications.map(observedProcess(from:))))
     }
 
+    public func apply(_ config: RuleConfig) throws {
+        try store.save(config)
+        dispatch(.configChanged(store.config))
+        reconcile()
+    }
+
+    public func reloadFromDisk() {
+        store.load()
+        dispatch(.configChanged(store.config))
+        reconcile()
+    }
+
     public func stop() {
@@ -123,6 +181,10 @@ public final class WatchController {
 
     private func dispatch(_ input: EngineInput) {
         perform(engine.handle(input, at: Now(wall: Date())))
+        // Единственная воронка, через которую проходит каждый вход, — поэтому и
+        // единственная точка уведомления. Строго после `perform`.
+        onStateChanged?()
     }
```

(Доккомментарии в диффе выше сокращены для читаемости; в файле они на месте. Ни одной строки
существующей логики не изменено и не удалено — только вставки.)

### Дифф `TerminatorApp.swift` (шов 6 и замена вью)

```diff
@@ -20,23 +20,9 @@ struct TerminatorApp: App {
     @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
 
-    /// Какие глаза показывает глиф в меню-баре. Один булев бит, живущий во вью-слое.
-    ///  … (доккомментарий, целиком) …
-    @State private var glyphEyes: MenuBarGlyphEyes = .idle
-
     var body: some Scene {
         MenuBarExtra {
-            PlaceholderView(glyphEyes: $glyphEyes)
+            PopoverView(model: appDelegate.popover)
         } label: {
@@ -46,7 +32,10 @@ struct TerminatorApp: App {
-            Image(nsImage: menuBarSkullImage(eyes: glyphEyes))
+            //
+            // Бит приезжает из модели, которая живёт в AppDelegate: глаза обязаны быть
+            // верны, когда поповер закрыт и его вью не существует.
+            Image(nsImage: menuBarSkullImage(eyes: appDelegate.popover.eyes))
         }
         .menuBarExtraStyle(.window)
     }
@@ -64,9 +53,17 @@ final class AppDelegate: NSObject, NSApplicationDelegate {
-    private let controller = WatchController(store: ConfigStore())
+    let controller = WatchController(store: ConfigStore())
+
+    /// Модель поповера (TASK-006). Держится **здесь**, а не во вью: состояние глаз глифа
+    /// обязано быть верным, когда поповер закрыт и его вью не существует.
+    private(set) lazy var popover = PopoverModel(controller: controller)
 
     func applicationDidFinishLaunching(_ notification: Notification) {
+        // Ровно одно присваивание и ровно один раз. Слот заполняется до `start()`.
+        controller.onStateChanged = { [weak self] in self?.popover.refresh() }
         controller.start()
     }
 }
```

Хранилище, движок, наблюдатель, отправитель и таймеры создаются как создавались:
`WatchController(store: ConfigStore())` и `controller.start()` — те же две конструкции.

## Не запускалось

### Приложение не запускалось — и почему

`./build.sh` собрал и подписал бандл, но `open build/Terminator.app` **не выполнялся**. Причина
конкретная, а не осторожность вообще: в системе уже висит процесс **прошлой** сборки —

```
$ ps -p 76503 -o pid,lstart,command
  PID STARTED                      COMMAND
76503 Sat Aug 29 06:18:32 2026     /Users/as.sorokin/Developer/own/terminator/build/Terminator.app/Contents/MacOS/Terminator
$ ls -la build/Terminator.app/Contents/MacOS/Terminator
-rwxr-xr-x@ 1 as.sorokin  staff  1283472 Aug 29 08:24 build/Terminator.app/Contents/MacOS/Terminator
```

— то есть запущенный бинарь на диске уже заменён новым. `open` на тот же бандл активировал бы
существующий процесс, а не запустил новый, так что проверка ничего бы не показала. Остановить
старый экземпляр можно только кнопкой «Quit Terminator» в его поповере: он `LSUIElement`, дока и
меню приложения у него нет, а сигналы (`kill`, `SIGTERM`) в этом проекте запрещены.

**Первое, что нужно сделать человеку:** открыть старый поповер (череп в меню-баре), нажать
«Quit Terminator», затем `./build.sh && open build/Terminator.app`.

Остаточный риск: краш на старте или нерисующийся поповер не пойман — компилятор и юнит-тесты
такого не ловят. Логика, которую можно было проверить без запуска, вынесена в ядро и покрыта
14 тестами; непокрытым остался слой SwiftUI и `NSOpenPanel`.

### Конфиг на диске на момент сдачи

```
$ cat ~/Library/Application\ Support/com.svvoff.terminator/config.json
{
  "rules" : {
    "com.apple.TextEdit" : {
      "limit" : { "kind" : "constant", "limitSeconds" : 3600 }
    }
  },
  "schemaVersion" : 1
}
```

Одно правило, **выключенное** (`enabledAt` отсутствует). Ни один чужой процесс во время
исполнения не завершался и завершиться не мог.

### Ручной чеклист — двенадцать пунктов, которые засчитывает человек

Ни один из них исполнителем не выполнен и не засчитан. Нумерация карточки в редакции
амендментов (пункт 6 струкнут; пункт 4 без оговорки `targetNotRunning`; пункт 11 только про
`refused`; пункт 14 в редакции пакета).

К каждому пункту лог читается дословно этой командой:

```
log show --predicate 'subsystem == "com.svvoff.terminator"' --style compact --last 1h
```

1. Пункт меню-бара появляется, клик открывает поповер window-стиля, и содержимое при каждом
   открытии свежее. **Ключевой вопрос: срабатывает ли `.onAppear` на каждое открытие** — на нём
   стоит перечитывание файла и пункт 14.
2. Первый запуск без правил: ровно одна строка о том, что делает Terminator, плюс контрол
   добавления и кнопка Quit — и ничего больше. (Чтобы получить пустое состояние, уберите
   правило для TextEdit кнопкой «−».)
3. Контрол добавления открывает `NSOpenPanel`, предлагающую только бандлы приложений.
   **Дополнительно, ровно по оговорке пакета: закрывает ли панель поповер, забирая key-статус?**
   Ответ нужен в отчёте оркестратору. Смягчение уже заложено — `notice` переживает закрытие и
   виден при следующем открытии, но само поведение измеряет человек.
4. Добавление **незапущенного** приложения проходит и создаёт правило.
5. Выбор бандла, у которого идентификатор `nil`, показывает видимое сообщение и правила **не**
   создаёт. Годный подопытный — `.app`-каталог без `CFBundleIdentifier` в `Info.plist`,
   собранный руками во временном каталоге. В логе при этом:
   `rule not created, bundle has no identifier: path=…`.
6. — струкнут амендментом 1.
7. Лимит 0, −1, 481 и нецелое (`12.5`) закоммитить нельзя: поле возвращает прежнее значение,
   в поповере появляется строка отказа.
8. Лимит на запущенном приложении: отсчёт в `m:ss` уменьшается при открытом поповере, остаётся
   верным после закрытия и повторного открытия, и показывает `h:mm:ss` для лимита больше 60
   минут. На `0:00` приложение закрывается в пределах одного тика (5 с).
9. Выключение правила останавливает отсчёт **мгновенно**; повторное включение перезапускает его
   с полного лимита даже для приложения, запущенного давно; смена одного лимита отсчёт **не**
   перезапускает. Это тот пункт, ради которого `apply(_:)` заканчивается `reconcile()`.
10. Глаза глифа красные, пока идёт отсчёт, и потушены, когда не идёт. **Если глиф не
    перерисовывается при смене состояния — это стоп-условие 4 пакета: находка, а не повод чинить
    `.id(…)`.** Здесь же проверяется реактивность `@Observable`-модели в теле сцены — форма
    другая, чем измеренный в §8 `@State`, и подтверждения на устройстве у неё пока нет.
11. Терминальное `refused` после исчерпанной лестницы ретраев (терминал на +150 с) видно в
    строке и отличимо от идущего отсчёта. Подопытный — приложение с несохранённым документом.
12. Два экземпляра одного приложения (`open -n`) дают **два** остатка, каждый подписан своим pid.
13. При нескольких правилах порядок: запущенные по возрастанию остатка, затем незапущенные,
    затем выключенные.
14. **В редакции пакета:** испортить файл (обрезать или поставить `schemaVersion: 2`) → закрыть
    и снова открыть поповер → баннер «Rules are read-only» виден → попытка правки видимо
    отклонена строкой, а файл на диске остался нетронутым. В логе:
    `quarantine entered, file left untouched: …`, затем
    `popover opened with quarantined store, edits will be refused: …`, затем при попытке правки
    `save refused, store is quarantined: …` и `edit refused: bundle=… reason=…`.
15. Finder добавляется, и ничто этому не мешает; записать, что происходит при его истечении.
    Гард не добавлять.

Отдельным требованием: поповер прогоняется в **светлой и тёмной** темах — кость черепа
перерешается под тему, глаза нет (§8).

## Проверка скоупа

```
$ git status --short
D  Sources/Terminator/PlaceholderView.swift
 M Sources/Terminator/TerminatorApp.swift
 M Sources/TerminatorAppKit/WatchController.swift
?? Sources/Terminator/PopoverModel.swift
?? Sources/Terminator/PopoverView.swift
?? Sources/TerminatorCore/PopoverViewModel.swift
?? Tests/TerminatorCoreTests/PopoverViewModelTests.swift

 M docs/ai/current-context.md                       ← не моё, изменения оркестратора
RM docs/product/backlog/.../TASK-006-menu-bar-popover.md ← не моё (перемещение + амендмент 2)
?? docs/ai/handoff/current-task-packet-popover.md   ← не моё (пакет)
```

Запрещённые зоны не тронуты:

- **редьюсер, арифметика дедлайнов, стратегия истечения, каденции, `perform`, `QuitSender`** —
  `Sources/TerminatorCore/WatchEngine.swift`, `ExpiryAction.swift`, `QuitSender.swift`,
  `EngineEffect.swift`, `EngineInput.swift` отсутствуют в диффе целиком;
- **сборка графа в `AppDelegate`** — `WatchController(store: ConfigStore())` и
  `controller.start()` не изменены; добавлены ровно одно свойство и одно присваивание;
- **`dispatch(_:)` остался `private`**; движок снаружи не мутируется;
- **`Limit.seconds` остался internal** — вью-модель в ядре им не пользуется, она считает через
  `Limit.wholeMinutes` и `Duration`;
- **модель правила, схема конфига, долговечная запись, правило карантина** (`Rule.swift`,
  `RuleConfig.swift`, `ConfigFormat.swift`, `ConfigStore.swift`, `DurableWrite.swift`) —
  не изменены. `RuleRejectionReason.editorMessage` добавлено **расширением в новом файле**
  вью-модели, сам `Rule.swift` не тронут;
- **починки/миграции/перезаписи карантинного файла нет** — `reloadFromDisk()` только читает;
- **`.appFirstObserved`** — ветка в `perform` не изменена, потребителя по-прежнему нет;
- **рисование черепа, `build.sh`, `Package.swift`, `NSStatusItem`, сцена `Settings`** — не
  тронуты и не заведены;
- **файлы соседнего потока** (`current-task-packet.md`, `current-execution-report.md`,
  `current-task-packet-loginitem.md`, `current-execution-report-loginitem.md`,
  `TASK-008-launch-at-login.md`) не читались и не изменялись;
- отдельного файла ручного чеклиста не создано — пункты перечислены выше в этом отчёте.

## Риски

1. **Реактивность лейбла меню-бара на `@Observable`.** §8 измерил реактивность на `@State` в
   `App`; здесь бит приезжает из `@Observable`-модели, которую держит `AppDelegate`, потому что
   амендмент 2 требует, чтобы модель пережила закрытие поповера, а `@State` в сцене этого не
   даёт. Форма другая, и на устройстве она не проверена. Пункт 10 чеклиста — единственный
   способ узнать. Обходов (`.id(…)`, пересоздание сцены) в коде нет и не должно появиться:
   расхождение — стоп-условие 4.
2. **`NSOpenPanel` и key-статус поповера.** Пакет прямо просит измерить; измерить без человека
   нельзя. Смягчение в коде: `notice` не сбрасывается при открытии поповера, поэтому отказ виден
   при следующем открытии, даже если панель поповер закрыла.
3. **Фокус в поле лимита при секундном перерендере.** `TimelineView` перевычисляет содержимое
   раз в секунду. Идентичность строк стабильна (`ForEach(id: \.bundleIdentifier)`), поэтому
   `NSTextField` пересоздаваться не должен, но на устройстве это не проверено — сидит внутри
   пункта 7 чеклиста. Механизм самообновления взят дословно из пакета, своего `Timer` нет.
4. **Два умолчания, которых нет ни в карточке, ни в пакете**, и это решения оркестратора, а не
   мои: новое правило создаётся **включённым** (`enabledAt = Date()`) и с лимитом **60 минут**
   (`PopoverModel.defaultLimitMinutes`). Выбраны так, потому что «добавил приложение — оно
   ничего не делает» противоречит смыслу единственного контрола добавления, а 60 — середина
   `Limit.allowedMinutes`. Если оркестратор решит иначе, это правка двух строк в
   `PopoverModel.addApplication()`.
5. **Человекочитаемое имя приложения не резолвится**: в строке показан голый `bundleIdentifier`.
   Пакет это разрешает явно («Показать голый bundle id — приемлемо»), и это же убирает целый
   класс расхождений между показанным именем и ключом сопоставления.
6. **Правило для уже добавленного приложения не перезаписывается.** Формально карточка про этот
   случай молчит; молчаливая перезапись через `set(_:)` переякорила бы дедлайн (новый
   `enabledAt`) без ведома пользователя, поэтому выбран отказ строкой.

## Незавершённое и follow-up

- Весь `manual-checklist` (12 пунктов) — человеку. До него задача не приёмная.
- Старый экземпляр Terminator (pid 76503) остался запущенным. Останавливается кнопкой в его
  поповере; сигналами — нельзя.
- Строка автозапуска и `LoginItemService` намеренно не трогались: их владелец — TASK-008,
  которая идёт следующим раундом (амендмент 2, «whichever runs second owns it»).
- Стоп-условий не сработало: шести швов хватило, шестого публичного символа в чужой зоне не
  понадобилось, ни одно измерение решению или findings не противоречило, ни один тест не
  ослаблялся, подпись прошла.
