# Отчёт об исполнении — TASK-006, раунд 3 (поток `-popover`)

## Задача

TASK-006, амендмент 4: отказ на пути «Add App…» невидим, потому что панель закрывает поповер,
в котором живёт строка `notice`. Проверять выбор нужно **внутри панели**, через
`NSOpenPanelDelegate.panel(_:validate:)`, бросая ошибку.

## Кратко

В `PopoverModel` добавлен вложенный тип `AddApplicationValidator` (`NSObject`,
`NSOpenSavePanelDelegate`) и **одно хранимое свойство** `addPanelValidator`, которое его держит.
`addApplication()` перед `runModal()` отдаёт валидатору снимок списка и присваивает
`panel.delegate`. Валидатор бросает `NSError` ровно на двух условиях — нет `bundleIdentifier`
и правило уже есть, — панель их показывает сама и не закрывается. Оба гарда после `runModal()`
сохранены как запасной путь; для случая «уже в списке» добавлена недостающая лог-строка.

Изменён один файл. Ноль строк `warning:` в debug и release, 83 теста в 8 сьютах, `build.sh`
EXIT=0.

## Поправка к пакету (инструкция пакета была ошибочной)

Пакет требует для новой лог-строки «категорию `popover`». **Такой категории в дереве нет.**
`TerminatorCore/LoggingIdentity.swift` содержит закрытый список из шести: `engine`, `quit`,
`consent`, `store`, `focus`, `loginitem`. Завести седьмую значило бы править
`Sources/TerminatorCore/` — запрещённую зону этого раунда.

Исполнено по второй половине той же фразы («по образцу соседней»): строка пишется существующим
`popoverLog` (`PopoverModel.swift:15`, категория `store`) — тем же логгером и в том же формате,
что соседняя `rule not created, bundle has no identifier`. Оркестратор подтвердил эту трактовку
отдельным сообщением по ходу работы. `LoggingIdentity.swift` не тронут (см. «Проверка скоупа»).

## Изменённые файлы

| Файл | Что изменено |
|---|---|
| `Sources/Terminator/PopoverModel.swift` | +64 строки, 0 удалено: вложенный `AddApplicationValidator`, хранимое свойство `addPanelValidator`, две строки проводки в `addApplication()`, лог-строка в существующем гарде «уже в списке» |

Больше не изменено ничего. `docs/ai/handoff/current-execution-report-popover.md` — этот отчёт.

## Дифф дословно

```diff
@@ -256,6 +256,59 @@ final class PopoverModel {

     // MARK: - Действия пользователя

+    /// Валидатор выбора в панели добавления, **удерживаемый хранимым свойством**.
+    ///
+    /// `NSOpenPanel.delegate` — слабая ссылка. Делегат, созданный инлайн в
+    /// `addApplication()`, освободился бы сразу после присваивания: `panel(_:validate:)` не
+    /// вызвался бы ни разу, панель закрывалась бы по-прежнему, отказ снова уходил бы в
+    /// невидимую строку `notice` — и дефект выглядел бы неисправленным, молча. Сильная
+    /// ссылка живёт здесь, панель одалживает её на время `runModal()`.
+    private let addPanelValidator = AddApplicationValidator()
+
+    /// Проверка выбора **внутри** панели: панель, отклонившая выбор, не закрывается и сама
+    /// показывает причину — пользователь остаётся в том же диалоге и может выбрать другое
+    /// приложение, не открывая поповер заново.
+    ///
+    /// Зачем это здесь, а не в `notice`: путь добавления — единственный в поповере, который
+    /// открывает модальную панель, а открытие панели закрывает сам поповер вместе со
+    /// строкой `notice`. Отказ, поднятый после `runModal()`, пользователю уже не виден;
+    /// поднятый отсюда — виден в момент действия.
+    ///
+    /// Проверяются ровно два условия и только они: нет `bundleIdentifier` и правило для него
+    /// уже есть. Ни подпись, ни платформа, ни запущенность не проверяются — обёрнутое
+    /// iOS-приложение законная цель, его идентификатор резолвится через `Wrapper/`.
+    private final class AddApplicationValidator: NSObject, NSOpenSavePanelDelegate {
+
+        /// Идентификаторы, у которых правило уже есть. Снимок, снятый перед `runModal()`:
+        /// пока панель модальна, ни один путь записи конфига не исполняется, так что снимок
+        /// и живой конфиг совпадают на всё время проверки.
+        var identifiersOnTheList: Set<String> = []
+
+        /// Формулировка отказа читается внутри открытой панели, поэтому говорит о самом
+        /// выборе, а не о ненаступившем последствии: правило здесь ещё и не начинали
+        /// создавать.
+        func panel(_ sender: Any, validate url: URL) throws {
+            guard let bundleIdentifier = Bundle(url: url)?.bundleIdentifier else {
+                throw Self.refusal(
+                    "\(url.lastPathComponent) has no bundle identifier and cannot be put on a time limit."
+                )
+            }
+            guard !identifiersOnTheList.contains(bundleIdentifier) else {
+                throw Self.refusal("\(bundleIdentifier) is already on the list.")
+            }
+        }
+
+        /// Панель показывает `localizedDescription` брошенной ошибки сама. Своей поверхности
+        /// — ни алерта, ни окна, ни второй модальной — здесь не заводится.
+        private static func refusal(_ message: String) -> NSError {
+            NSError(
+                domain: TerminatorLog.subsystem + ".addapplication",
+                code: 1,
+                userInfo: [NSLocalizedDescriptionKey: message]
+            )
+        }
+    }
+
     /// Добавление приложения: панель выбора, `Bundle(url:)`, правило.
     ///
     /// Панель отфильтрована по типу содержимого `.application`. Это единственный механизм
@@ -273,6 +326,11 @@ final class PopoverModel {
         panel.message = "Choose an application to put on a time limit."
         panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

+        // Снимок списка отдаётся валидатору перед показом панели, а сам валидатор — сильная
+        // ссылка на хранимом свойстве: `panel.delegate` слабая и локальный объект не удержит.
+        addPanelValidator.identifiersOnTheList = Set(config.rules.keys)
+        panel.delegate = addPanelValidator
+
         // Приложение `.accessory` (`LSUIElement=true`, findings §7) не активируется ничем в
         // дереве: открытие поповера даёт временное key-окно, но не активацию. Модальная панель
         // неактивного приложения получает окно, которое не является key, и первые клики уходят
@@ -282,6 +340,11 @@ final class PopoverModel {

         guard panel.runModal() == .OK, let url = panel.url else { return }

+        // Оба гарда ниже — запасной путь: при живом валидаторе панель не закрывается и сюда
+        // такой выбор не доходит. Сработавший гард означает, что `panel(_:validate:)` не
+        // выполнился, то есть делегат умер, — и лог-строка будет единственным свидетельством
+        // этого, потому что `notice` пользователь на этом пути не увидит.
+        //
         // Идентификатор берётся из бандла, а не из имени файла: сопоставление идёт по точной
         // строке `bundleIdentifier` и ни по чему больше (findings §10).
         guard let bundleIdentifier = Bundle(url: url)?.bundleIdentifier else {
@@ -292,6 +355,7 @@ final class PopoverModel {

         guard config.rule(for: bundleIdentifier) == nil else {
             notice = "\(bundleIdentifier) is already on the list."
+            popoverLog.notice("rule not created, bundle already on the list: bundle=\(bundleIdentifier, privacy: .public)")
             return
         }
```

## Чем удерживается делегат — главное место ревью

Ссылка сильная и удерживается **хранимым свойством самой модели**:

```swift
private let addPanelValidator = AddApplicationValidator()
```

- Это `let` на `PopoverModel`, инициализируемый на месте объявления, то есть объект создаётся
  вместе с моделью и живёт ровно столько же. `PopoverModel` держит `AppDelegate` (по её
  собственному doc-комментарию: «Живёт вне поповера»), поэтому валидатор переживает и открытие,
  и закрытие панели, и закрытие поповера.
- `panel.delegate = addPanelValidator` **одалживает** ссылку: слабая ссылка панели указывает на
  объект, у которого владелец есть и без неё. Локальной переменной, которую панель не удержала
  бы, в коде нет вообще — конструкции `let delegate = ...` внутри `addApplication()` не
  появилось.
- Цикла удержания нет: валидатор не ссылается на модель ни сильно, ни слабо. Вместо ссылки ему
  передаётся значение — `Set<String>` идентификаторов, снятое перед `runModal()`. Пока панель
  модальна, ни один путь записи конфига не исполняется, поэтому снимок и живой `config`
  совпадают на всё время проверки.
- `panel.delegate` не обнуляется после `runModal()` намеренно: панель — локальный объект и
  умирает вместе с вызовом, а валидатор переиспользуется следующим нажатием «Add App…».

### Статическое доказательство, что метод виден AppKit

Приложение не запускалось (запрет пакета), поэтому вызов делегата проверен по собранному бинарю:
метод экспортирован в ObjC-рантайм под точно тем селектором, который зовёт `NSSavePanel`.

```
$ otool -v -s __TEXT __objc_methname build/Terminator.app/Contents/MacOS/Terminator | grep -i validateURL
00000001000ae013  panel:validateURL:error:

$ nm -m build/Terminator.app/Contents/MacOS/Terminator | grep AddApplicationValidator | grep panel
00000001000090f8 (__TEXT,__text) ... LLC5panel_8validateyyp_10Foundation3URLVtKF
0000000100009958 (__TEXT,__text) ... LLC5panel_8validateyyp_10Foundation3URLVtKFTo
```

Суффикс `To` — ObjC-точка входа (thunk) для swift-метода; её наличие вместе со строкой селектора
`panel:validateURL:error:` в `__objc_methname` означает, что метод зарегистрирован в
ObjC-рантайме и достижим для AppKit. Строка селектора могла попасть в бинарь только из нашей
реализации: сами мы этот селектор нигде не вызываем. Класс собран как ObjC-класс
(`_OBJC_METACLASS_$__TtCC10Terminator12PopoverModelP..._23AddApplicationValidator`).

Это доказывает достижимость, но **не** доказывает, что панель показала сообщение: последнее
проверяет человек (см. «Не запускалось»).

## Изменения поведения

1. Выбор бандла без `CFBundleIdentifier` в панели «Add App…»: панель **остаётся открытой** и
   показывает `<имя>.app has no bundle identifier and cannot be put on a time limit.` Правило не
   создаётся, `notice` не выставляется, в лог ничего не пишется — потому что до кода после
   `runModal()` дело не доходит.
2. Выбор приложения, уже имеющегося в списке: панель остаётся открытой и показывает
   `<bundle id> is already on the list.`
3. Тексты переписаны под чтение **внутри панели**: «No rule was created» ушло из формулировки
   отказа, потому что в момент показа правило ещё и не начинали создавать. Смысл и длина
   сохранены. Строки `notice` в гардах после `runModal()` не тронуты — они читаются в поповере,
   где прежняя формулировка верна.
4. Новая лог-строка на запасном пути «уже в списке»:
   `rule not created, bundle already on the list: bundle=<id>` — `privacy: .public` на
   единственной интерполяции, категория `store` (логгер `popoverLog`, как у соседней строки).
5. Всё остальное на пути добавления не изменилось: фильтр `.application`, `prompt`, `message`,
   `directoryURL`, `NSApp.activate()` из раунда 2, поведение при отмене панели.

Ничего не проверяется сверх двух названных условий: ни подпись, ни платформа, ни запущенность.
Обёрнутое iOS-приложение проходит: проверка спрашивает только `Bundle(url:)?.bundleIdentifier`,
тем же вызовом, каким его резолвил принятый ранее путь (`org.khronos.gltf.glTFViewer`).

## Доказательства валидации

| Команда | Результат | Вывод |
|---|---|---|
| `rm -rf .build && swift build` | EXIT=0 | `Build complete! (15.77s)`, полная пересборка всех трёх таргетов с нуля |
| `grep -c "warning:" debug.log` | `0` | **ноль строк `warning:`** в debug |
| `swift build -c release` | EXIT=0 | `Build complete! (18.87s)` |
| `grep -c "warning:" release.log` | `0` | **ноль строк `warning:`** в release |
| `swift test` | EXIT=0 | `Test run with 83 tests in 8 suites passed after 0.132 seconds.` — ровно 83 в 8, новых не добавлено |
| `scripts/check-forbidden.sh .` | EXIT=0 | `OK:    запрещённых конструкций не найдено` |
| `./build.sh` | EXIT=0 | см. ниже |

`grep -n "warning:"` по обоим логам не дал ни одной строки (exit 1 — совпадений нет).

Вывод `./build.sh` дословно:

```
--- swift build -c debug ---
[0/1] Planning build
Building for debugging...
[0/3] Write swift-version--58304C5D6DBC2206.txt
Build complete! (0.20s)
--- assemble build/Terminator.app ---
--- codesign --force --sign "Terminator Dev" (последняя мутация бандла) ---
build/Terminator.app: replacing existing signature
--- designated requirement guard ---
designated requirement: identifier "com.svvoff.terminator" and certificate leaf = H"74d582911cd0b2c7ff3961af4bb0561efd6a8f24"
--- codesign --verify --strict (терминальный шаг) ---
EXIT=0
```

Ни одна команда не упала.

## Acceptance criteria (амендмент 4)

| Критерий | Статус | Чем подтверждён |
|---|---|---|
| Валидация выбора внутри панели через `NSOpenPanelDelegate.panel(_:validate:)`, с броском ошибки | выполнен (код), требует человека (показ) | дифф; селектор `panel:validateURL:error:` и thunk `…KFTo` в собранном бинаре |
| Ровно два условия: нет `bundleIdentifier`; правило уже есть | выполнен | дифф: два `guard`, третьей проверки нет |
| Делегат — хранимое свойство, не инлайн | выполнен | `private let addPanelValidator = AddApplicationValidator()`; локальной переменной-делегата в `addApplication()` нет |
| Существующие гарды после `runModal()` и их лог-строки сохранены | выполнен | дифф: 64 вставки, 0 удалений; обе `notice`-строки и `popoverLog.notice(…has no identifier…)` на месте |
| Для «уже в списке» добавлена лог-строка с `privacy: .public` | выполнен | дифф; категория — существующая `store` через `popoverLog` (см. «Поправка к пакету») |
| Тексты читаются внутри открытой панели | выполнен | «No rule was created» в текстах панели отсутствует |
| Нет `NSAlert`, окна, второй модальной поверхности | выполнен | `grep -rn "NSAlert\|NSWindow(" Sources/` — совпадений нет; показывает ошибку сама панель |
| Поведение поповера не обходится и не перестилизовывается | выполнен | `PopoverView.swift`, `TerminatorApp.swift` не изменены |
| `notice` на других путях отказа не изменён | выполнен | дифф: строки `notice` вне `addApplication()` не тронуты |
| Юнит-тестов не добавлено, валидация не вынесена в ядро | выполнен | `swift test` — те же 83 в 8; `Sources/TerminatorCore/` не изменён |
| Ноль строк `warning:` в debug и release | выполнен | счётчики выше |
| Панель действительно остаётся открытой и показывает причину | **требует человека** | пункт 5 переписанного чеклиста |

## Не запускалось

**Приложение не запускалось** — прямой запрет пакета, поэтому ни один сценарий с открытой
панелью не проклацан. Юнит-теста нет и не будет: `NSOpenPanel` и его делегат headless не
сконструировать; мок не изобретался, валидация в ядро не выносилась.

Человеку остаётся ровно один пункт — переписанный **пункт 5** ручного чеклиста, на собранном
`build/Terminator.app`:

1. Открыть поповер, нажать «Add App…».
2. Выбрать бандл без `CFBundleIdentifier` (у автора это `OpenSC Notify.app`) и нажать «Add».
   Ожидание: **панель не закрывается**, показывает
   `OpenSC Notify.app has no bundle identifier and cannot be put on a time limit.`; после
   закрытия сообщения панель всё ещё открыта, правило не создано.
3. Не закрывая панель, выбрать приложение, **уже имеющееся в списке**, и нажать «Add».
   Ожидание: та же механика, сообщение `<bundle id> is already on the list.`
4. Выбрать нормальное приложение — оно добавляется как прежде; отдельно стоит повторить
   обёрнутое iOS-приложение (`org.khronos.gltf.glTFViewer`), оно **должно проходить**.
5. Контрольная проверка лога — обе запасные строки не должны появиться ни разу:
   `/usr/bin/log show --predicate 'subsystem == "com.svvoff.terminator"' --style compact --last 15m | grep "rule not created"`
   Пустой вывод = валидатор жив. Любая из двух строк = делегат умер и панель закрылась, то есть
   починка не сработала.

Остаточный риск: если `panel(_:validate:)` на этой версии macOS почему-либо не вызовется, отказ
снова уйдёт в невидимую строку `notice` — но теперь это будет **видно в логе** обеими строками
пункта 5. Молчаливого отказа больше нет. Стоп-условие пакета соблюдено: на `NSAlert` я не
переходил и не буду — если пункт 5 провалится, это возврат карточки, а не обход.

## Проверка скоупа

```
$ git status --short
 M Sources/Terminator/PopoverModel.swift
 M docs/ai/handoff/current-task-packet-popover.md
 M docs/product/backlog/tasks/in-progress/TASK-006-menu-bar-popover.md

$ git diff --stat
 Sources/Terminator/PopoverModel.swift              |  64 +++++++++++
 docs/ai/handoff/current-task-packet-popover.md     | 121 ++++++++++++---------
 .../tasks/in-progress/TASK-006-menu-bar-popover.md | 113 ++++++++++++++++++-
```

Два `docs/`-файла — незакоммиченная работа оркестратора (пакет и амендмент 4), существовавшая до
моего первого действия; я их не открывал на запись. Единственный мой изменённый файл —
`Sources/Terminator/PopoverModel.swift`; плюс создан отчёт
`docs/ai/handoff/current-execution-report-popover.md`.

Запрещённые зоны не тронуты, проверено по `git status`:

- `Sources/TerminatorCore/` — не изменён (включая `LoggingIdentity.swift`: новой категории не
  заводил);
- `Sources/TerminatorAppKit/` — не изменён;
- `Sources/Terminator/TerminatorApp.swift`, `PopoverView.swift` — не изменены;
- `Package.swift`, `Packaging/Info.plist`, `build.sh`, подпись, keychain — не изменены;
- путь quit, Apple Events, расчёт дедлайна, модель правил — не тронуты;
- код учёта фокуса (TASK-007) — не тронут;
- `docs/` — кроме этого отчёта ничего не создано и не изменено; карточка и её амендменты не
  правились;
- `~/Library/` — ни чтения, ни записи; приложение не запускалось, конфиг не трогался;
- потоки `-focus`, `-loginitem` и общий `current-task-packet.md` не читались.

Изменение целиком лежит внутри `addApplication()`, одного хранимого свойства и одного приватного
вложенного типа, который это свойство держит. За эти границы не выходил.

## Риски

1. **Снимок вместо живого чтения.** Валидатор проверяет `Set<String>`, снятый перед
   `runModal()`. Пока панель модальна, `apply()` не вызывается ни по одному пути, так что
   разойтись с живым конфигом снимок не может. Если такой путь когда-нибудь появится, гард
   `config.rule(for:) == nil` после `runModal()` останется вторым рубежом.
2. **Формат показа зависит от AppKit.** Панель показывает `localizedDescription` брошенной
   ошибки своим средством; `NSLocalizedRecoverySuggestionErrorKey` не задан намеренно —
   сообщение одно и короткое. Как именно оно оформлено, покажет пункт 5.
3. **Домен ошибки** — `TerminatorLog.subsystem + ".addapplication"`, `code: 1` для обоих
   отказов. Пользователю домен и код не видны, наружу они не уходят; различаются отказы текстом.
4. Общее для раунда: единственный способ проверить работу поверхности — человек. Тестом это
   место не закрывается, и следующий дефект такого класса снова придёт от автора, а не от CI.

## Незавершённое и follow-up

Незавершённого по амендменту 4 нет. Открыто только исполнение пункта 5 человеком.

Наблюдение для оркестратора (сам не действовал): пакет назвал несуществующую категорию лога
`popover`. Если категория для поповера действительно нужна, это правка `TerminatorCore` и
отдельное решение, а не побочный эффект этого раунда.
