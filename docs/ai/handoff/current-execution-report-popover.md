# Отчёт об исполнении — TASK-006, раунд 4 (поток `-popover`)

## Задача

TASK-006, амендмент 5: строка списка опознаёт приложение только по bundle id, который
усекается по середине и нечитаем. Показать человекочитаемое имя приложения над
идентификатором.

Пакет: `docs/ai/handoff/current-task-packet-popover.md`.

## Кратко

Имена резолвятся один раз на открытие поповера — `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`
→ `FileManager.default.displayName(atPath:)`, — и кладутся в приватный словарь `PopoverModel`
по bundle id. Строка правила показывает имя обычным body-шрифтом первой строкой и
идентификатор caption-моноширинным под ним; когда имя не резолвится, первой строкой остаётся
идентификатор, а вторичная строка не выводится.

`TerminatorCore` не тронут: `PopoverViewModel`, `PopoverRow` и сортировка не меняются.
Изменены ровно два разрешённых файла. Тестов не добавлено и не убрано — 83 в 8 сьютах.

## Изменённые файлы

| Файл | Что изменено |
|---|---|
| `Sources/Terminator/PopoverModel.swift` | приватный словарь `displayNames`, `func displayName(for:)`, `private func resolveDisplayNames()`, вызов резолва в `popoverDidOpen()` после `refresh()` |
| `Sources/Terminator/PopoverView.swift` | `RuleRowView`: `primaryLabel` (имя или идентификатор), `identifierLine` (вторичная строка с идентификатором), `displayName` — чтение словаря модели |

Больше в рабочем дереве изменено ничего, кроме этого отчёта. `current-task-packet-popover.md`
и карточка TASK-006 числятся модифицированными — это правки оркестратора, я их не трогал.

## Где живёт кэш и когда заполняется

```swift
private var displayNames: [String: String] = [:]
```

— хранимое свойство `PopoverModel`, приватное; наружу только `displayName(for:)`.

Заполняется **ровно в одном месте** — `resolveDisplayNames()`, — и зовётся оно **ровно из
одного места**: `popoverDidOpen()`, порядок вызовов там теперь такой:

```swift
controller.reloadFromDisk()
refresh()
resolveDisplayNames()   // ← после refresh(): по набору правил, только что пришедшему с диска
readLoginItemStatus()
```

Резолв стоит после `refresh()`, а не до: `refresh()` — это то место, где снимок `config`
обновляется с контроллера. Резолв до него прошёлся бы по прошлому набору правил, и правило,
дописанное в файл руками, осталось бы без имени до следующего открытия.

Словарь пересобирается целиком на каждое открытие (`var resolved` → присваивание), поэтому
удалённое правило не оставляет за собой записи, а переустановленное приложение резолвится
заново. В `body` вью резолва нет: там только `displayNames[bundleIdentifier]` — чтение
словаря. Содержимое поповера перерисовывается раз в секунду (`TimelineView(.periodic(by: 1))`),
и запрос в LaunchServices на строку на кадр был бы платой за значение, которое при открытом
поповере не меняется. Дисциплина ровно та же, что уже применена к статусу автозапуска.

Имя нигде не сериализуется: в `config.json` по-прежнему уходит только `bundleIdentifier`,
DTO не тронут вовсе (`Sources/TerminatorCore/` — запрещённая зона этого раунда).

## Что происходит, когда имя не резолвится

`urlForApplication(withBundleIdentifier:)` вернул `nil` (приложение не установлено — случай
настоящий: правило переживает удаление приложения) — идентификатор в словарь **не
записывается**. Пустая строка тоже не записывается: `guard !name.isEmpty else { continue }`.
Отсутствие ключа — единственное представление случая «имени нет», второго флага нет.

Во вью это даёт ровно одну строку вместо двух:

- `primaryLabel` показывает `row.bundleIdentifier` с `.font(.system(.body, design: .monospaced))`
  — то есть строка выглядит в точности так, как выглядела до этого раунда;
- `identifierLine` не выводится вовсе (`if displayName != nil`), чтобы один и тот же
  идентификатор не стоял в строке дважды.

`.help(row.bundleIdentifier)` навешан на месте вызова и потому присутствует в обеих ветках.

## Дифф

```diff
diff --git a/Sources/Terminator/PopoverModel.swift b/Sources/Terminator/PopoverModel.swift
@@ -78,6 +78,17 @@ final class PopoverModel {
     /// перерисовывается раз в секунду (findings §14).
     private(set) var loginItemStatus: LoginItemStatus?
 
+    /// Человекочитаемые имена приложений, снятые на текущее открытие поповера.
+    ///
+    /// Ключ — bundle id, значение — то же имя, которое показывает Finder. Идентификатор, для
+    /// которого имя не нашлось, в словаре **отсутствует**: правило переживает удаление
+    /// приложения, и пустая строка на месте имени была бы хуже самого идентификатора.
+    ///
+    /// Словарь живёт только в памяти. В `config.json` имя не попадает никогда: это сменило бы
+    /// человекочитаемый контракт на диске ради значения, которое протухает от переименования,
+    /// смены языка или замены приложения.
+    private var displayNames: [String: String] = [:]
+
     /// Регистрация записана, но система ещё не сообщает включённое состояние.
@@ -119,6 +130,10 @@ final class PopoverModel {
     func popoverDidOpen() {
         controller.reloadFromDisk()
         refresh()
+        // Строго после `refresh()`: имена резолвятся по тому набору правил, который только что
+        // пришёл с диска, иначе правило, дописанное в файл руками, осталось бы без имени до
+        // следующего открытия.
+        resolveDisplayNames()
         readLoginItemStatus()
         if let quarantine {
             let reason = String(describing: quarantine)
@@ -126,6 +141,46 @@ final class PopoverModel {
         }
     }
 
+    /// Имя приложения для строки списка. `nil` означает «не резолвится» — приложение не
+    /// установлено, а правило его пережило; вью в этом случае показывает идентификатор.
+    func displayName(for bundleIdentifier: String) -> String? {
+        displayNames[bundleIdentifier]
+    }
+
+    /// Резолв имён — **одно чтение на открытие поповера, а не на кадр**.
+    ///
+    /// Содержимое поповера перерисовывается раз в секунду ради отсчёта, а
+    /// `urlForApplication(withBundleIdentifier:)` — запрос в LaunchServices. Один запрос на
+    /// строку на кадр был бы платой за значение, которое при открытом поповере не меняется. Та
+    /// же дисциплина уже применена к статусу автозапуска: одно чтение на открытие.
+    ///
+    /// **Имя берётся у Finder, а не из `Info.plist`.** Ключи не годятся: `CFBundleDisplayName`
+    /// у `com.tdesktop.Telegram` отсутствует, а обёрнутое iOS-приложение
+    /// `org.khronos.gltf.glTFViewer` не несёт на верхнем уровне даже каталога `Contents/` —
+    /// его настоящий бандл лежит под `Wrapper/`, и `CFBundleName` там читается как
+    /// `glTFViewer`, без пробела, то есть не так, как это приложение называет Finder.
+    /// Реализация через ключи выглядит правильной и молча даёт то отсутствие, то не то имя;
+    /// `displayName(atPath:)` вдобавок отдаёт локализованное имя.
+    ///
+    /// Имя — presentation и ничего больше: в сортировку, в фильтрацию и ни в одно решение оно
+    /// не входит. Порядок строк остаётся за ядром — по остатку, затем по `bundleIdentifier`.
+    private func resolveDisplayNames() {
+        var resolved: [String: String] = [:]
+        resolved.reserveCapacity(config.rules.count)
+        for bundleIdentifier in config.rules.keys {
+            guard
+                let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
+            else {
+                // Приложение не установлено. Случай настоящий: правило переживает удаление
+                // приложения, и строка обязана остаться на месте — со своим идентификатором.
+                continue
+            }
+            let name = FileManager.default.displayName(atPath: url.path)
+            guard !name.isEmpty else { continue }
+            resolved[bundleIdentifier] = name
+        }
+        displayNames = resolved
+    }
+
     // MARK: - Автозапуск
```

```diff
diff --git a/Sources/Terminator/PopoverView.swift b/Sources/Terminator/PopoverView.swift
@@ -161,8 +161,7 @@ private struct RuleRowView: View {
                 .toggleStyle(.switch)
                 .controlSize(.mini)
 
-                Text(row.bundleIdentifier)
-                    .font(.system(.body, design: .monospaced))
+                primaryLabel
                     .lineLimit(1)
                     .truncationMode(.middle)
                     .help(row.bundleIdentifier)
@@ -188,12 +187,59 @@ private struct RuleRowView: View {
                 .help("Remove this rule")
             }
 
+            identifierLine
+
             statusLines
         }
         .onAppear { limitText = displayedLimit }
         .onChange(of: row.limitMinutes) { _, _ in limitText = displayedLimit }
     }
 
+    /// Имя приложения на текущее открытие поповера. Резолв сделан один раз в
+    /// `popoverDidOpen()`; здесь — только чтение словаря, потому что тело вью выполняется
+    /// раз в секунду.
+    private var displayName: String? {
+        model.displayName(for: row.bundleIdentifier)
+    }
+
+    /// Первая строка правила: имя приложения, если оно резолвится, иначе идентификатор.
+    ///
+    /// Имя идёт обычным body-шрифтом: моноширинный нужен идентификатору, у которого значим
+    /// каждый символ, а не имени. Подсказка `.help(...)` с полным идентификатором висит на
+    /// этой строке в обоих случаях — она навешана на месте вызова.
+    @ViewBuilder
+    private var primaryLabel: some View {
+        if let displayName {
+            Text(displayName)
+        } else {
+            // Приложение не установлено, имени нет. Строка выглядит ровно так, как выглядела
+            // до появления имён.
+            Text(row.bundleIdentifier)
+                .font(.system(.body, design: .monospaced))
+        }
+    }
+
+    /// Идентификатор под именем. Отдельной строкой, а не припиской к статусу: приписка
+    /// читается в ветке без экземпляров и разваливается во второй, где статусных строк
+    /// столько же, сколько запущенных экземпляров.
+    ///
+    /// Идентификатор остаётся на виду намеренно: это точный ключ сопоставления (findings §10),
+    /// он же лежит в `config.json`, который автор правит руками, и он же печатается в каждой
+    /// строке лога. Когда имя не резолвится, идентификатор уже стоит первой строкой — и здесь
+    /// не повторяется.
+    @ViewBuilder
+    private var identifierLine: some View {
+        if displayName != nil {
+            Text(row.bundleIdentifier)
+                .font(.system(.caption, design: .monospaced))
+                .foregroundStyle(.secondary)
+                // Длинный идентификатор переносится, а не усекается: усечение по середине на
+                // первой строке — ровно тот дефект, из-за которого имя и появилось.
+                .fixedSize(horizontal: false, vertical: true)
+                .padding(.leading, 30)
+        }
+    }
+
     private var displayedLimit: String {
```

## Два решения, принятых внутри границ пакета, — названы, а не спрятаны

1. **`.lineLimit(1)` и `.truncationMode(.middle)` остались на первой строке** и теперь
   применяются к результату `primaryLabel`, то есть и к имени тоже. Имя короче
   идентификатора и в отведённую ширину влезает; поведение при экзотически длинном имени
   остаётся тем же, что было у идентификатора, и не заводит новой ветки вёрстки.
2. **Вторичная строка с идентификатором переносится, а не усекается**
   (`.fixedSize(horizontal: false, vertical: true)`, без `lineLimit`). Пакет задал шрифт,
   цвет и отступ, но не задал поведение при нехватке ширины. Усечение по середине здесь
   воспроизвело бы ровно тот дефект, ради которого написан амендмент, — идентификатор,
   который нельзя прочесть; при ширине поповера 340 pt и отступе 30 pt четыре реальных
   идентификатора автора умещаются в одну строку, и перенос сработает только на более
   длинном. Если оркестратор предпочитает усечение — это правка одной строки.

## Доказательства валидации

Все команды запущены из корня репозитория. Счётчики `warning:` — это
`grep -c 'warning:' <лог сборки>` по полному выводу команды.

| Команда | Результат | Вывод |
|---|---|---|
| `rm -rf .build && swift build` | EXIT=0, **warnings=0** | `Build complete! (11.33s)` — полная пересборка с нуля |
| `swift build -c release` | EXIT=0, **warnings=0** | `Build complete! (10.14s)` |
| `swift test` | EXIT=0, warnings=0 | `✔ Test run with 83 tests in 8 suites passed after 0.216 seconds.` |
| `scripts/check-forbidden.sh` | EXIT=0 | `OK:    запрещённых конструкций не найдено` |
| `./build.sh` | EXIT=0 | designated requirement совпал, `codesign --verify --strict` — терминальный шаг |

После этого прогона я поправил один док-комментарий в `PopoverModel.swift` (см. «Расхождение
с таблицей амендмента») и прогнал всё заново — уже инкрементально:

```
debug EXIT=0 warnings=0
release EXIT=0 warnings=0
test EXIT=0 warnings=0
✔ Test run with 83 tests in 8 suites passed after 0.136 seconds.
OK:    запрещённых конструкций не найдено
forbidden EXIT=0
build.sh EXIT=0
```

Полный вывод `./build.sh` последнего прогона:

```
--- swift build -c debug ---
[0/1] Planning build
Building for debugging...
[0/3] Write swift-version--58304C5D6DBC2206.txt
Build complete! (0.14s)
--- assemble build/Terminator.app ---
--- codesign --force --sign "Terminator Dev" (последняя мутация бандла) ---
build/Terminator.app: replacing existing signature
--- designated requirement guard ---
designated requirement: identifier "com.svvoff.terminator" and certificate leaf = H"74d582911cd0b2c7ff3961af4bb0561efd6a8f24"
--- codesign --verify --strict (терминальный шаг) ---
```

Восемь сьютов, поимённо, последний прогон:

```
✔ Suite "Доменная модель правила" passed after 0.094 seconds.
✔ Suite "Движок наблюдения" passed after 0.094 seconds.
✔ Suite "Формат конфига на диске" passed after 0.101 seconds.
✔ Suite "Автозапуск: содержимое plist и отображение статуса" passed after 0.110 seconds.
✔ Suite "Вью-модель поповера" passed after 0.110 seconds.
✔ Suite "Учёт фокуса" passed after 0.111 seconds.
✔ Suite "Хранилище конфига: карантин, уборка, путь" passed after 0.115 seconds.
✔ Suite "Долговечная запись" passed after 0.136 seconds.
✔ Test run with 83 tests in 8 suites passed after 0.136 seconds.
```

Тест сортировки, названный пакетом поимённо, — зелёный:

```
✔ Test equalRemainingTimesBreakTieByBundleIdentifier() passed after 0.090 seconds.
```

### Стоп-условие 2 проверено отдельно: энтайтлмент и диалог согласия

`urlForApplication(withBundleIdentifier:)` — вызов LaunchServices, не Apple Event и не TCC.
Проверено **вне приложения** (приложение не запускалось): одноразовая программа в
скретчпаде — `/private/tmp/.../scratchpad/probe.swift`, собрана `swiftc`, запущена как
неподписанный некапсулированный CLI-процесс, то есть в условиях **строго слабее** боевых
(нет бандла, нет подписи, нет Info.plist).

```
com.apple.TextEdit | url=/System/Applications/TextEdit.app | displayName=TextEdit | CFBundleDisplayName=TextEdit | CFBundleName=TextEdit
com.tdesktop.Telegram | url=/Applications/Telegram.app | displayName=Telegram | CFBundleDisplayName=<absent> | CFBundleName=Telegram
org.khronos.gltf.glTFViewer | url=/Applications/glTF Viewer.app | displayName=glTF Viewer | CFBundleDisplayName=glTF Viewer | CFBundleName=glTFViewer
com.apple.printcenter | url=/System/Applications/Utilities/Print Center.app | displayName=Print Center | CFBundleDisplayName=Print Center | CFBundleName=Print Center
com.example.definitely.not.installed | url=nil | displayName=<none>
EXIT=0
```

Вывод: **ни энтайтлмента, ни диалога согласия**. Все четыре идентификатора резолвятся
мгновенно и синхронно, ни один диалог не поднялся, процесс завершился с кодом 0. Пятая
строка — синтетический неустановленный идентификатор: `url=nil`, то есть ветка «имени нет»
достижима и наблюдаема. Останавливаться по стоп-условию 2 не потребовалось.

Резолв `displayName(atPath:)` даёт ровно те имена, которые названы в чеклисте:
`com.apple.printcenter` → **Print Center**, `org.khronos.gltf.glTFViewer` → **glTF Viewer**.

### Расхождение с таблицей амендмента — сообщаю, не чиню

Таблица амендмента 5 говорит про `org.khronos.gltf.glTFViewer`: `CFBundleDisplayName` —
**absent**, `CFBundleName` — **absent**. Мой замер через `Bundle(url:)` показал оба ключа
присутствующими: `CFBundleDisplayName=glTF Viewer`, `CFBundleName=glTFViewer`.

Причина расхождения, проверенная на диске:

```
$ ls -la "/Applications/glTF Viewer.app/"
lrw-r--r--  WrappedBundle -> Wrapper/glTFViewer.app
drwxr-xr-x  Wrapper
$ ls "/Applications/glTF Viewer.app/Contents/"
ls: /Applications/glTF Viewer.app/Contents/: No such file or directory
```

Каталога `Contents/` действительно нет — тут амендмент точен. Но `Bundle(url:)` проходит
через `WrappedBundle` во внутренний бандл и читает его `Info.plist`, поэтому ключи через
Foundation-API видны, хотя по пути `Contents/Info.plist` их нет. Замер амендмента,
по-видимому, снят по файловому пути, а не через `Bundle`.

**Вывод амендмента от этого не меняется, и реализация не меняется тем более:**
`CFBundleDisplayName` отсутствует у `com.tdesktop.Telegram` (это подтвердилось), а
`CFBundleName` у обёрнутого приложения читается как `glTFViewer` — без пробела, то есть **не
тем именем**, которым это приложение зовётся в Finder и в чеклисте. Путь через ключи
`Info.plist` остаётся неверным; он просто ломается не отсутствием, а неправильным значением.
Я привёл док-комментарий в `resolveDisplayNames()` в соответствие с измеренным, чтобы в коде
не остался комментарий, утверждающий непроверяемое. Карточку не правил — это зона
оркестратора.

## Acceptance criteria (амендмент 5)

| Критерий | Статус | Чем подтверждён |
|---|---|---|
| Имя из `urlForApplication` → `displayName(atPath:)`, без `CFBundleDisplayName`/`CFBundleName` | выполнен | дифф `resolveDisplayNames()`; ключи Info.plist в продакшн-коде не читаются вовсе |
| Резолв в `popoverDidOpen()` после `reloadFromDisk()`, кэш по bundle id | выполнен | дифф `popoverDidOpen()`; единственный вызов `resolveDisplayNames()` |
| Ни одного резолва на кадр | выполнен | во вью только `model.displayName(for:)` — чтение словаря; `NSWorkspace` в `PopoverView.swift` не упоминается |
| Primary — имя, body-шрифт, не моноширинный, `.help(...)` сохранён | выполнен | дифф `primaryLabel` + `.help(row.bundleIdentifier)` на месте вызова |
| Вторичная строка — идентификатор: caption, моноширинный, `.secondary`, отступ 30 | выполнен | дифф `identifierLine` |
| Статусные строки ниже, без изменений | выполнен | `statusLines` в диффе не тронут |
| Имя не резолвится → primary = идентификатор, вторичной строки нет | выполнен | дифф обеих веток; ветка `url=nil` наблюдалась в пробнике |
| `TerminatorCore` не тронут | выполнен | `git status --short` — ни одного файла из `Sources/TerminatorCore/` |
| Сортировка не изменена | выполнен | `equalRemainingTimesBreakTieByBundleIdentifier` зелёный; порядок строк по-прежнему целиком в ядре |
| Имя не сохраняется в `config.json` | выполнен | словарь приватен и живёт в памяти; DTO и путь записи не тронуты |
| Новых строк лога нет | выполнен | в диффе нет ни одного `popoverLog`/`loginItemLog` |
| Иконок, поиска, группировки нет | выполнен | дифф |
| Тестов ровно 83 в 8 сьютах | выполнен | `swift test` |
| Ноль `warning:` в debug и release | выполнен | `warnings=0` в обеих конфигурациях, в т.ч. на полной пересборке с нуля |
| **Чеклист, пункт 16** | **требует человека** | см. ниже |

## Не запускалось

**Приложение не запускалось** — пакет это запрещает, и `./build.sh` собран, но бандл не
открывался.

**Юнит-теста нет и не заводился.** Резолв зависит от `NSWorkspace`, LaunchServices и от того,
что установлено на машине; мок-`NSWorkspace` запрещён не-целями карточки, а выносить резолв в
ядро ради тестируемости запрещено пакетом и противоречит форме ядра (окружение оно не читает
по конструкции). Замена — пробник в скретчпаде выше: он доказывает поведение самих API на
этой машине, но **не** доказывает вёрстку строки.

**Остаточный риск** — целиком в вёрстке: что именно увидит человек, тестом здесь не
устанавливается вовсе.

### Пункт 16 чеклиста — засчитывает человек

`./build.sh && open build/Terminator.app`, затем открыть поповер и проверить построчно:

1. каждая строка показывает читаемое имя приложения первой строкой, обычным (не моноширинным)
   шрифтом, а под ним — идентификатор мелким моноширинным серым;
2. `com.apple.printcenter` читается как **Print Center**, `org.khronos.gltf.glTFViewer` — как
   **glTF Viewer**;
3. правило неустановленного приложения показывает **идентификатор** первой строкой и **не**
   показывает ни пустого имени, ни идентификатора дважды (проверяется правилом, приложение
   которого удалено или переименовано);
4. наведение на первую строку по-прежнему показывает подсказку с полным идентификатором;
5. порядок строк не изменился — по остатку, затем по идентификатору, не по имени;
6. отсчёт в статусных строках продолжает тикать раз в секунду (резолв ничего не заморозил).

## Проверка скоупа

```
$ git status --porcelain
 M Sources/Terminator/PopoverModel.swift
 M Sources/Terminator/PopoverView.swift
 M docs/ai/handoff/current-task-packet-popover.md
 M docs/product/backlog/tasks/in-progress/TASK-006-menu-bar-popover.md
```

Изменены ровно два файла, разрешённые пакетом (плюс этот отчёт). Два документа помечены
модифицированными до начала моей работы — это правки оркестратора: пакет и карточка. Я их не
открывал на запись.

Запрещённые зоны не тронуты: `Sources/TerminatorCore/` и `Sources/TerminatorAppKit/` целиком,
`TerminatorApp.swift`, `Package.swift`, `Packaging/Info.plist`, `build.sh`, подпись, keychain,
путь quit, Apple Events, расчёт дедлайна, модель правил, всё про учёт фокуса, `~/Library/` в
любом виде. `NSApp.activate()` из раунда 2 и валидатор панели из раунда 3 остались дословно
такими же — в диффе их нет. Соседние потоки (`-focus`, `-loginitem`, безымянный) не читались.

Временные файлы — только в скретчпаде сессии, вне репозитория.

## Риски

1. **Вёрстка не проверена глазами.** Строка стала двухуровневой в одной ветке и одноуровневой
   в другой; как это выглядит на настоящем списке, устанавливает только человек. Строка стала
   выше — при большом списке поповер вырастет по высоте.
2. **Стоимость открытия выросла на N запросов в LaunchServices**, где N — число правил.
   Запрос синхронный, и на четырёх правилах он незаметен; на списке в сотни правил открытие
   поповера подтормаживало бы. Ограничения на число правил в продукте нет — но и списка в
   сотни правил у MVP нет.
3. **Имя может разойтись с логом и конфигом.** Именно поэтому идентификатор остался видимым;
   риск снят конструкцией, а не дисциплиной чтения.

## Незавершённое и follow-up

Ничего не осталось незавершённым в границах амендмента 5.

Возможные темы для оркестратора — **решения не мои**:

1. Расхождение таблицы амендмента 5 с измерением через `Bundle(url:)` по
   `org.khronos.gltf.glTFViewer` (см. выше). Вывод амендмента верен, обоснование одной ячейки
   — нет. Правка карточки — зона оркестратора.
2. Поведение вторичной строки при нехватке ширины (перенос против усечения) выбрано мной
   внутри границ пакета и названо явно; если предпочтителен другой вариант — это одна строка.
