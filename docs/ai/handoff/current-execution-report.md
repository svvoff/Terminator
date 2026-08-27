# Отчёт об исполнении

## Задача

**TASK-002, раунд 3 — амендмент 2:** состояние глаз глифа переключается кнопкой из
плейсхолдера, лейбл `MenuBarExtra` рендерится из этого состояния.

Пакет: `docs/ai/handoff/current-task-packet.md`.
Карточка: `docs/product/backlog/tasks/in-progress/TASK-002-package-and-app-bundle.md`,
секция «Amendment 2 · 2026-08-27».

Этот отчёт **перезаписывает** отчёт раунда 2 (так велит пакет; раунды 1 и 2 приняты,
переделкой они не были и не затронуты).

## Кратко

Состояние глаз поднято в `TerminatorApp` как единственный `@State`, лейбл `MenuBarExtra`
рендерится из него прямой формой `Image(nsImage: menuBarSkullImage(eyes: glyphEyes))`.
`PlaceholderView` получил `@Binding` на это состояние, строку с текущим состоянием и кнопку,
которая его переключает; заголовок кнопки называет состояние, **в которое** она переключит.
Дифф — ровно два файла в `Sources/`; ни движка, ни хранилища, ни наблюдателя, ни таймера, ни
делегата не появилось. `MenuBarGlyph.swift`, `build.sh`, `Package.swift`, `Packaging/Info.plist`
не тронуты по содержимому (об mtime — см. «Проверка скоупа», там есть одна оговорка, которую я
обязан назвать).

Обходных механизмов реактивности (`.id(...)`, пересоздание сцены, ручной `objectWillChange`,
таймер) нет: форма прямая, и вопрос «перерисовался ли лейбл» вынесен человеку как измерение.

## Изменённые файлы

| Файл | Что изменено |
|---|---|
| `Sources/Terminator/TerminatorApp.swift` | Добавлен `@State private var glyphEyes: MenuBarGlyphEyes = .idle` с комментарием (владелец — TASK-006, причина — амендмент 2 и Review trigger DEC-009, уезжает вместе с плейсхолдером). Лейбл рендерится из него; `PlaceholderView` получает `$glyphEyes`. Устаревшая строка комментария «Глиф пришпилен к idle» заменена на пояснение прямой реактивной формы. |
| `Sources/Terminator/PlaceholderView.swift` | Добавлен `@Binding var glyphEyes` с тем же комментарием о владельце; добавлен блок 2 — строка `menu bar glyph: <текущее>` и кнопка `Switch to <другое>`; добавлено `fileprivate`-расширение `MenuBarGlyphEyes` с `placeholderTitle` и `flipped`; блоки фактов и Quit перенумерованы 2→3 и 3→4, заголовок дока «три вещи» → «четыре вещи». |
| `docs/ai/handoff/current-execution-report.md` | Этот отчёт. |

Больше ничего. Никаких новых файлов.

### Реальный дифф двух файлов

Файлы в `Sources/` не отслеживаются git (`?? Sources/`), поэтому `git diff` их не показывает.
Как и в раунде 2 с `build.sh`, версия раунда 2 восстановлена **дословно** во временный файл вне
репозитория и сопоставлена с текущей через `diff -u`.

```diff
--- round2/TerminatorApp.swift
+++ Sources/Terminator/TerminatorApp.swift
@@ -12,17 +12,33 @@
 @main
 struct TerminatorApp: App {

+    /// Какие глаза показывает глиф в меню-баре. Один булев бит, живущий во вью-слое.
+    ///
+    /// Владелец бита — **TASK-006**: там «идёт ли хоть один отсчёт» выводится из состояния
+    /// движка, и это состояние приезжает сюда вместо `@State`. Здесь оно существует только
+    /// ради **амендмента 2** к TASK-002 и Review trigger DEC-009: различимость красных глаз
+    /// от idle проверяется в самом меню-баре, а туда состояние попадает единственным путём —
+    /// через лейбл, то есть через `App`.
+    ///
+    /// За этим флагом нет ни движка, ни хранилища, ни наблюдателя, ни таймера, и он ничего
+    /// ни из чего не выводит: его переключает рукой кнопка в `PlaceholderView`. Композиционный
+    /// корень — по-прежнему TASK-004. В TASK-006 флаг уезжает вместе с плейсхолдером,
+    /// который его переключает; переизобретать его как проводку движка не нужно.
+    @State private var glyphEyes: MenuBarGlyphEyes = .idle
+
     var body: some Scene {
         MenuBarExtra {
-            PlaceholderView()
+            PlaceholderView(glyphEyes: $glyphEyes)
         } label: {
             // Готовый Image(nsImage:) и ничего больше. Произвольное SwiftUI-вью
             // компилируется, но не соблюдается: лейбл принимает только Text, Image
             // или Label, а .symbolRenderingMode(.palette) сплющивается в template
             // и теряет красные глаза (findings §8).
             //
-            // Глиф пришпилен к idle: живое переключение глаз — TASK-006.
-            Image(nsImage: menuBarSkullImage(eyes: .idle))
+            // Прямая реактивная форма: состояние → готовый образ. Никаких .id(...),
+            // пересозданий сцены и ручных инвалидаций — на реактивности этого лейбла
+            // строится TASK-006, и если её нет, это измерение, а не повод обходить.
+            Image(nsImage: menuBarSkullImage(eyes: glyphEyes))
         }
         .menuBarExtraStyle(.window)
     }
```

```diff
--- round2/PlaceholderView.swift
+++ Sources/Terminator/PlaceholderView.swift
@@ -2,10 +2,19 @@
 import SwiftUI
 import TerminatorAppKit

-/// Плейсхолдер поповера. Настоящий поповер — TASK-006; здесь ровно три вещи, и каждая
+/// Плейсхолдер поповера. Настоящий поповер — TASK-006; здесь ровно четыре вещи, и каждая
 /// нужна для приёмки TASK-002.
 struct PlaceholderView: View {

+    /// Состояние глаз глифа в меню-баре, поднятое в `TerminatorApp`.
+    ///
+    /// Владелец — **TASK-006**: там этот бит выводится из состояния движка, а плейсхолдер
+    /// вместе с кнопкой ниже заменяется целиком и уезжает. Существует ради **амендмента 2**
+    /// и Review trigger DEC-009: пара образцов ниже отвечает на вопрос «различимы ли версии
+    /// рядом», а кнопка — на вопрос «различимы ли они в меню-баре», и ответить на него можно
+    /// только оттуда. Это не проводка движка: за биндингом нет ничего, кроме нажатия кнопки.
+    @Binding var glyphEyes: MenuBarGlyphEyes
+
     /// Считается в момент появления вью, а не в `init()` приложения.
     @State private var runtimeFacts: RuntimeFacts?

@@ -21,9 +30,25 @@
                 glyphSample("active", eyes: .active)
             }

+            // 2. Ручное переключение глаз глифа **в меню-баре** (амендмент 2).
+            //    Владелец состояния — TASK-006: там бит приходит из движка, а этот
+            //    плейсхолдер вместе с кнопкой исчезает. Кнопка существует ровно затем,
+            //    чтобы закрыть Review trigger DEC-009 — сравнение idle и active делается
+            //    на фоне меню-бара, а не на фоне поповера. Ни движка, ни таймера за ней
+            //    нет; заголовок называет состояние, В КОТОРОЕ она переключит, а строка
+            //    выше — состояние, которое показывает бар прямо сейчас.
+            VStack(alignment: .leading, spacing: 6) {
+                Text("menu bar glyph: \(glyphEyes.placeholderTitle)")
+                    .font(.system(.caption, design: .monospaced))
+
+                Button("Switch to \(glyphEyes.flipped.placeholderTitle)") {
+                    glyphEyes = glyphEyes.flipped
+                }
+            }
+
             Divider()

-            // 2. Единственный канал доказательства для двух acceptance criteria.
+            // 3. Единственный канал доказательства для двух acceptance criteria.
             VStack(alignment: .leading, spacing: 4) {
                 Text(runtimeFacts?.activationPolicyLine ?? "activationPolicy: —")
                 Text(runtimeFacts?.bundleIdentifierLine ?? "bundleIdentifier: —")
@@ -33,7 +58,7 @@

             Divider()

-            // 3. У LSUIElement-приложения нет ни дока, ни меню: без этой кнопки
+            // 4. У LSUIElement-приложения нет ни дока, ни меню: без этой кнопки
             //    единственный способ его остановить — сигнал. Закрытие себя —
             //    штатное действие (DEC-006); запрет DEC-002 касается чужих приложений.
             Button("Quit Terminator") {
@@ -59,6 +84,28 @@
     }
 }

+/// Имя состояния и его переключение нужны только плейсхолдеру: это подписи и кнопка
+/// амендмента 2, а не часть глифа. Поэтому они живут здесь и `fileprivate`, а
+/// `MenuBarGlyph.swift` о них не знает — рисующая функция уже принимает состояние
+/// параметром, ровно поэтому амендмент маленький. В TASK-006 уезжает вместе с
+/// плейсхолдером.
+extension MenuBarGlyphEyes {
+
+    fileprivate var placeholderTitle: String {
+        switch self {
+        case .idle: "idle"
+        case .active: "active"
+        }
+    }
+
+    fileprivate var flipped: MenuBarGlyphEyes {
+        switch self {
+        case .idle: .active
+        case .active: .idle
+        }
+    }
+}
+
 /// Два факта об окружении, которые невозможно получить иначе как из запущенного бандла:
 /// голый SwiftPM-исполняемый файл даёт `.prohibited` и `bundleIdentifier == nil`
 /// (findings §7).
```

Пара образцов idle/active в поповере и всё остальное (`RuntimeFacts` и печать в stdout из
`.onAppear`, показ `activationPolicy` и `bundleIdentifier`, кнопка Quit,
`.menuBarExtraStyle(.window)`, отсутствие `setActivationPolicy`) — в диффе отсутствуют, то есть
не изменены.

## Изменения поведения

- Глиф в меню-баре больше не пришпилен к `.idle`: он рендерится из `glyphEyes`. Начальное
  значение — `.idle`, персистентности нет, перезапуск начинает с idle (не-цель соблюдена).
- В поповере появилась строка `menu bar glyph: idle` / `active` и кнопка `Switch to active` /
  `Switch to idle`. Заголовок кнопки — целевое состояние, строка — текущее.
- Тип лейбла не изменился: это по-прежнему заранее сконфигурированный `Image(nsImage:)`,
  findings §8 не затронут. `.symbolRenderingMode`, произвольного SwiftUI-вью и прочих форм
  лейбла в коде нет.
- Ошибок Sendable/конкурентности не возникло вовсе: состояние — `Sendable`-перечисление в
  MainActor-изолированной `App` (у таргета `defaultIsolation(MainActor.self)`), кнопка
  захватывает `Binding`, а не изменяемое состояние. Ни один запрещённый эскейп-хетч не
  понадобился — см. грепы ниже.

## Доказательства валидации

Все команды выполнены из корня репозитория, `2026-08-27`.

| Команда | Результат | Вывод |
|---|---|---|
| `swift build` | EXIT=0 | ниже, блок 1 |
| `swift build -c release` (с форсированной перекомпиляцией) | EXIT=0, `warning:` — 0 строк | ниже, блок 2 |
| `./build.sh --self-test-guard` | EXIT=0, 4 из 4 вердиктов | ниже, блок 3 |
| `./build.sh` | EXIT=0, DR-гейт пройден, подпись проверена | ниже, блок 4 |
| `scripts/check-forbidden.sh` | EXIT=0 | ниже, блок 5 |
| грепы по эскейп-хетчам и проводке движка | 0 совпадений в коде | ниже, блок 6 |
| `git status --short --untracked-files=all`, `stat`, `shasum` | дифф — два файла | раздел «Проверка скоупа» |

### Блок 1 — `swift build`

```
$ swift build 2>&1; echo "EXIT=$?"
[0/1] Planning build
Building for debugging...
[0/4] Write sources
[1/4] Write swift-version--58304C5D6DBC2206.txt
[3/7] Compiling Terminator PlaceholderView.swift
[4/7] Emitting module Terminator
[5/7] Compiling Terminator TerminatorApp.swift
[5/8] Write Objects.LinkFileList
[6/8] Linking Terminator
[7/8] Applying Terminator
Build complete! (2.05s)
EXIT=0
```

### Блок 2 — `swift build -c release`, вывод целиком

Первый прогон (компилировал изменённый таргет):

```
$ swift build -c release 2>&1; echo "EXIT=$?"
Building for production...
[0/6] Write sources
[3/6] Write swift-version--58304C5D6DBC2206.txt
[5/7] Compiling TerminatorCore LoggingIdentity.swift
[6/8] Compiling TerminatorAppKit MenuBarGlyph.swift
[7/9] Compiling Terminator PlaceholderView.swift
[7/9] Write Objects.LinkFileList
[8/9] Linking Terminator
Build complete! (7.03s)
EXIT=0
```

Счётчик предупреждений:

```
$ swift build -c release 2>&1 | grep -c "warning:"
0
```

Этот второй прогон был инкрементальным и ничего не компилировал, поэтому 0 из него —
доказательство слабое. Прогон с форсированной перекомпиляцией **всех** исходников
(`touch` по `Sources/**/*.swift`, затем release-сборка), вывод целиком:

```
$ touch Sources/Terminator/*.swift Sources/TerminatorAppKit/*.swift Sources/TerminatorCore/*.swift && swift build -c release 2>&1; echo "EXIT=$?"
Building for production...
[0/5] Write sources
[3/5] Write swift-version--58304C5D6DBC2206.txt
[5/6] Compiling TerminatorCore LoggingIdentity.swift
[6/7] Compiling TerminatorAppKit MenuBarGlyph.swift
[7/8] Compiling Terminator PlaceholderView.swift
Build complete! (1.38s)
EXIT=0
```

Ни одной строки `warning:` во всём выводе. (Цена этого `touch` — испорченные mtime двух
нетронутых файлов; полностью раскрыто в «Проверке скоупа».)

### Блок 3 — `./build.sh --self-test-guard`

```
$ ./build.sh --self-test-guard 2>&1; echo "EXIT=$?"
--- self-test гейта (ничего не собирается и не подписывается) ---
ожидаемый designated requirement: identifier "com.svvoff.terminator" and certificate leaf = H"74d582911cd0b2c7ff3961af4bb0561efd6a8f24"
  OK   ad-hoc подпись (cdhash) -> reject
  OK   чужой сертификат (другой хеш листа) -> reject
  OK   уехавший CFBundleIdentifier -> reject
  OK   ожидаемый текст дословно -> accept
self-test: 4 из 4 вердиктов верны
EXIT=0
```

Гейт раунда 2 не сломан.

### Блок 4 — `./build.sh` (последняя мутирующая команда этого раунда)

```
$ ./build.sh 2>&1; echo "EXIT=$?"
--- swift build -c debug ---
Building for debugging...
[0/3] Write swift-version--58304C5D6DBC2206.txt
Build complete! (0.11s)
--- assemble build/Terminator.app ---
--- codesign --force --sign "Terminator Dev" (последняя мутация бандла) ---
build/Terminator.app: replacing existing signature
--- designated requirement guard ---
designated requirement: identifier "com.svvoff.terminator" and certificate leaf = H"74d582911cd0b2c7ff3961af4bb0561efd6a8f24"
--- codesign --verify --strict (терминальный шаг) ---
EXIT=0
```

Состояние бандла сразу после (никаких мутаций `Contents/` после `codesign` не было — подпись
последняя, как требует findings §6):

```
$ stat -f '%Sm %N' -t '%Y-%m-%d %H:%M:%S' build/Terminator.app build/Terminator.app/Contents/MacOS/Terminator
2026-08-27 15:40:53 build/Terminator.app
2026-08-27 15:40:53 build/Terminator.app/Contents/MacOS/Terminator

$ codesign -dv build/Terminator.app
Executable=/Users/as.sorokin/Developer/own/terminator/build/Terminator.app/Contents/MacOS/Terminator
Identifier=com.svvoff.terminator
Format=app bundle with Mach-O thin (arm64)
CodeDirectory v=20400 size=590 flags=0x0(none) hashes=12+3 location=embedded
Signature size=1668
Signed Time=27 Aug 2026 at 15:40:53
Info.plist entries=9
TeamIdentifier=not set
```

В `build/` лежит свежий подписанный бандл со всеми изменениями этого раунда — для последнего
пункта ручного чеклиста. Приложение **не запускалось**.

### Блок 5 — `scripts/check-forbidden.sh`

```
$ scripts/check-forbidden.sh 2>&1; echo "EXIT=$?"
OK:    запрещённых конструкций не найдено
EXIT=0
```

### Блок 6 — грепы по эскейп-хетчам и по проводке движка

Счётчики совпадений по всему `Sources/` (`grep -rn -F`):

```
@unchecked Sendable              : 0
@preconcurrency                  : 0
swiftLanguageMode                : 0
NSApplicationDelegateAdaptor     : 1
NSApplicationDelegate            : 1
Timer                            : 0
@Observable                      : 0
ObservableObject                 : 0
objectWillChange                 : 0
.id(                             : 1
actor                            : 0
class                            : 0
UserDefaults                     : 0
DispatchQueue                    : 0
```

Оба ненулевых совпадения — комментарии, кода за ними нет:

```
$ grep -rn -F -- 'NSApplicationDelegateAdaptor' Sources/
Sources/Terminator/TerminatorApp.swift:7:/// Композиционного корня здесь нет и быть не должно: ни `NSApplicationDelegateAdaptor`,

$ grep -rn -F -- '.id(' Sources/
Sources/Terminator/TerminatorApp.swift:38:            // Прямая реактивная форма: состояние → готовый образ. Никаких .id(...),
```

(`NSApplicationDelegate` даёт то же единственное совпадение — это подстрока той же строки 7.)

## Acceptance criteria

Дополнительные критерии из секции «Amendment 2».

| Критерий | Статус | Чем подтверждён |
|---|---|---|
| Лейбл `MenuBarExtra` рендерится из одного куска view-состояния, кнопка в плейсхолдере переключает его idle↔active; лейбл по-прежнему заранее сконфигурированный `Image(nsImage:)` | выполнен (визуальная часть — требует человека) | Дифф обоих файлов выше: `@State private var glyphEyes`, `Image(nsImage: menuBarSkullImage(eyes: glyphEyes))`, `Button("Switch to …") { glyphEyes = glyphEyes.flipped }`. Тип лейбла не менялся. Что бар **действительно** перерисовывается — пункт 3 ручного чеклиста. |
| Заголовок кнопки называет состояние, в которое переключает; плейсхолдер показывает текущее | выполнен | `Text("menu bar glyph: \(glyphEyes.placeholderTitle)")` и `Button("Switch to \(glyphEyes.flipped.placeholderTitle)")` — заголовок строится из `flipped`, строка из текущего значения. |
| И состояние, и кнопка несут комментарий: владелец TASK-006, причина — амендмент 2 и Review trigger DEC-009, уезжают вместе с плейсхолдером | выполнен | Три комментария в диффе: над `@State`, над `@Binding`, над блоком 2. Каждый называет TASK-006 владельцем, амендмент 2 и DEC-009 причиной и говорит, что уедет с плейсхолдером. |
| В `Sources/Terminator/` по-прежнему нет `NSApplicationDelegateAdaptor`, делегата, движка, хранилища, наблюдателя и таймера | выполнен | Блок 6: все счётчики 0, кроме двух комментариев. Добавлены ровно `@State`-перечисление, `@Binding`, `Button` и два `fileprivate`-свойства. |
| `Sources/TerminatorAppKit/MenuBarGlyph.swift` не изменён | выполнен по содержимому | Раздел «Проверка скоупа»: файл не открывался на запись; sha256 зафиксирован. Оговорка про mtime — там же. |

Требования пакета к реализации (п. 1–5) — все закрыты тем же диффом; п. 4 (пара образцов
остаётся) и п. 5 (остальное без изменений) подтверждаются отсутствием этих строк в диффе.

## Не запускалось

**Приложение не запускалось** — так велит пакет; `validation_profile` карточки включает
`manual-checklist`, и эти пункты исполнитель не засчитывает.

Что должен сделать человек, на свежем бандле `build/Terminator.app` (собран и подписан
`2026-08-27 15:40:53`, EXIT=0):

1. Запустить бандл:
   `./build/Terminator.app/Contents/MacOS/Terminator`
   (или через Finder — тогда строка stdout уйдёт в лог запуска; для видимого stdout лучше
   запускать из терминала). Кликнуть череп в меню-баре — откроется поповер.
2. **Переключение.** Нажать кнопку `Switch to active`. Ожидание: глиф **в меню-баре**
   становится active (красные глаза), строка над кнопкой меняется на `menu bar glyph: active`,
   заголовок кнопки — на `Switch to idle`. Нажать ещё раз — вернуться в idle.
3. **Review trigger DEC-009**, оба вопроса — про меню-бар, оба — в **светлой и тёмной** теме
   (System Settings → Appearance):
   - кость идёт за темой меню-бара (тёмная на светлом баре, светлая на тёмном);
   - красные глаза отличаются от idle **с одного взгляда**, и на светлом баре, и на тёмном;
   - маска читается как череп в меню-барном размере.
4. **Отдельно записать: перерисовался ли лейбл вообще.** Это измерение, а не побочная деталь:
   findings §8 говорит, какой **тип** лейбла переживает, но не говорит, реактивен ли он, а на
   его реактивности построена TASK-006. Если бар не меняется при нажатии — это результат,
   который надо доложить (обходного механизма в коде нет намеренно, см. п. 3 «самых дорогих
   ошибок» пакета).
5. Закрыть приложение кнопкой **Quit Terminator** в поповере.
6. Заодно, если поповер открыт: строки `activationPolicy:` и `bundleIdentifier:` — прежние
   пункты чеклиста раундов 1–2, кодом этого раунда не затронуты.

Остаточный риск: реактивность лейбла `MenuBarExtra` при смене `@State` в `App` агентом не
проверяема в принципе — меню-бар нельзя ни увидеть, ни нажать из субагента. Форма кода —
прямая и каноническая для SwiftUI; если она не сработает, это находка для findings §8, а не
повод чинить обходом.

## Проверка скоупа

`git status --short --untracked-files=all` (строки `?? build/…` отфильтрованы — это артефакты
сборки, `build/` в `.gitignore`):

```
 M docs/ai/current-context.md
 M docs/ai/handoff/current-execution-report.md
RM docs/product/backlog/tasks/ready/TASK-002-package-and-app-bundle.md -> docs/product/backlog/tasks/in-progress/TASK-002-package-and-app-bundle.md
 M docs/product/recon/macos-findings.md
?? Package.swift
?? Packaging/Info.plist
?? Sources/Terminator/PlaceholderView.swift
?? Sources/Terminator/TerminatorApp.swift
?? Sources/TerminatorAppKit/MenuBarGlyph.swift
?? Sources/TerminatorCore/LoggingIdentity.swift
?? build.sh
?? docs/ai/handoff/current-task-packet.md
```

Отслеживаемые изменения — работа **оркестратора** до этого раунда (`current-context.md`,
перемещение карточки в `in-progress/` с секцией амендмента, `macos-findings.md`, пакет) плюс
этот отчёт, лежащий в разрешённой зоне. Исполнитель их не трогал. `Sources/`, `Package.swift`,
`Packaging/`, `build.sh` — untracked целиком, git по ним дифф не показывает.

Не коммитил, веток не создавал.

### Оговорка про mtime — читать обязательно

В раунде 2 доказательством «untracked-файлы не тронуты» служили mtime. **В этом раунде я этот
канал испортил сам**: чтобы честно поймать `warning:` в release-сборке, я выполнил
`touch Sources/Terminator/*.swift Sources/TerminatorAppKit/*.swift Sources/TerminatorCore/*.swift`
и форсировал перекомпиляцию. `touch` сдвинул mtime и у двух файлов, которые я **не менял**:

```
$ find Sources Packaging scripts probes build.sh Package.swift .gitignore -type f \( -name '*.swift' -o -name '*.sh' -o -name '*.plist' -o -name '.gitignore' \) -exec stat -f '%Sm %N' -t '%Y-%m-%d %H:%M:%S' {} \; | sort
2026-08-26 16:52:26 .gitignore
2026-08-26 16:52:26 scripts/verify-docs.sh
2026-08-26 17:42:29 probes/task-001/run-probe.sh
2026-08-26 18:35:56 probes/task-001/build-probe.sh
2026-08-26 18:35:56 probes/task-001/main.swift
2026-08-26 18:36:07 probes/task-001/build/BuildTag.swift
2026-08-26 18:36:08 probes/task-001/build/Probe.app/Contents/Info.plist
2026-08-27 10:24:48 Package.swift
2026-08-27 10:27:41 Packaging/Info.plist
2026-08-27 15:26:59 build.sh
2026-08-27 15:38:23 Sources/Terminator/PlaceholderView.swift
2026-08-27 15:38:23 Sources/Terminator/TerminatorApp.swift
2026-08-27 15:38:23 Sources/TerminatorAppKit/MenuBarGlyph.swift
2026-08-27 15:38:23 Sources/TerminatorCore/LoggingIdentity.swift
```

Что здесь читается корректно и что нет:

- `Package.swift` (10:24:48), `Packaging/Info.plist` (10:27:41), `build.sh` (15:26:59),
  `scripts/`, `probes/`, `.gitignore` — mtime раунда 1/2, не тронуты. Это доказательство в
  силе: четыре запрещённых пакетом файла из шести именно здесь.
- `MenuBarGlyph.swift` и `LoggingIdentity.swift` — mtime **15:38:23 из-за моего `touch`**, а не
  из-за правки. Содержимое я не менял: за весь раунд открыты на запись были ровно два файла
  (`TerminatorApp.swift`, `PlaceholderView.swift`) и этот отчёт.

Восстанавливать сдвинутые mtime командой `touch -t` я **не стал сознательно**: это была бы
подделка доказательства, а не его восстановление. Правильнее назвать поломку вслух.

Чем это заменяется для ревью:

- содержимое `MenuBarGlyph.swift` открыто читаемо и сверяемо с версией, принятой в раунде 1
  (геометрия — порт `docs/product/design/menu-bar-icon-*.svg`, DEC-009);
- зафиксированы sha256, чтобы у следующих раундов был долговременный базис вместо mtime:

```
$ shasum -a 256 Sources/Terminator/*.swift Sources/TerminatorAppKit/*.swift Sources/TerminatorCore/*.swift Package.swift Packaging/Info.plist build.sh
aa6c93902765525a7cb108d8c48e28c7de21123f23637a3f492dba76cbd17685  Sources/Terminator/PlaceholderView.swift
fdd493d2e8f3ffbf5ee444aaa310943d904cdf16fe6a0d128cec69623063a64a  Sources/Terminator/TerminatorApp.swift
cb58eb72910532b1316da384cd7d1b85e1733d48a05c20fbd81f94bb9bdda1c7  Sources/TerminatorAppKit/MenuBarGlyph.swift
8c759f32a4cb2a0d4a9198d50dc138ba706f1dfbc76c84b666401295e3add2b5  Sources/TerminatorCore/LoggingIdentity.swift
519a20853fc88ad89d5936a7b461cd1b5edef61d09b7fb59d613f4856439f3da  Package.swift
4406625d2beda0d2005a91104d1f8e887faf0d69347d05cd8f130237442f219d  Packaging/Info.plist
3a03107040f564c78d86ba3e0c838a523ec23507bffd2cee3659fc04ffa044b5  build.sh
```

Запрещённые зоны из «Высокорисковых зон» в этом раунде не задеты: `codesign`/identity/DR-строку
не менял (`build.sh` не тронут), keychain не трогал, `tccutil` не запускал, чужие процессы не
завершал, в `~/Library/LaunchAgents/` не писал, формат конфига на диске не существует и не
менялся.

Файлы вне репозитория, созданные для доказательства (в скретчпаде сессии, не в дереве проекта):
восстановленные версии раунда 2 обоих изменённых файлов — только чтобы получить `diff -u`.

## Риски

1. **Реактивность лейбла не проверена и проверяема только человеком.** Если `MenuBarExtra`
   label не перерисовывается на смену `@State` в `App`, амендмент своей цели не достигнет, и
   допущение, на котором стоит TASK-006, окажется ложным. Обхода в коде нет намеренно; пункт 4
   ручного чеклиста ровно про это. Вероятность считаю низкой (форма каноническая), но
   измерения у меня нет.
2. **Испорченные mtime двух нетронутых файлов** (см. выше). Риск — процессный, не продуктовый:
   ревью теряет самый дешёвый канал проверки скоупа для `MenuBarGlyph.swift` и
   `LoggingIdentity.swift` и вынуждено смотреть содержимое. Впредь: форсировать перекомпиляцию
   лучше удалением каталога сборки, а не `touch` по исходникам.
3. **`fileprivate`-расширение `MenuBarGlyphEyes` живёт в `PlaceholderView.swift`.** Это
   сознательно: имена «idle»/«active» — подписи плейсхолдера, а не часть глифа, и трогать
   `MenuBarGlyph.swift` пакет запрещает. Побочный эффект — строковые литералы «idle»/«active»
   встречаются и в вызовах `glyphSample(...)` (код раунда 1, не менялся). Сводить их в одно
   место я не стал: это была бы правка за пределами необходимого. Если оркестратор считает
   дублирование нежелательным — это однострочная правка следующего раунда, а не дефект этого.
4. **`@Binding` вместо `@State` в плейсхолдере** делает `PlaceholderView` несоздаваемым без
   аргумента. Единственная точка создания — `TerminatorApp`, других нет и превью нет, так что
   на сборку это не влияет (подтверждено `swift build`).

## Незавершённое и follow-up

- Пункты ручного чеклиста (раздел «Не запускалось») — за человеком; они гейтят приёмку
  TASK-002 целиком и Review trigger DEC-009.
- Результат пункта 4 (реактивен ли лейбл `MenuBarExtra`) стоит записать в findings §8 —
  сейчас там сказано только, какой **тип** лейбла переживает. Правку findings делает
  оркестратор: карточка амендмента такого разрешения исполнителю не даёт.
- Открытые пункты раундов 1–2, не затронутые этим раундом (оговорка по строкам usage в
  `build.sh`, стареющий комментарий в ветке `--adhoc-control`), остаются как были.
- Возможная микроправка из риска 3 — на усмотрение оркестратора.
