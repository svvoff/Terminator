# Отчёт об исполнении

Раунд 2 карточки TASK-008. Пакет: `docs/ai/handoff/current-task-packet-loginitem.md`.

## Задача

TASK-008 — строка автозапуска в поповере (вызывающий для `LoginItemService`).

## Кратко

Добавлена одна строка поповера ниже `Divider()`: подпись «Launch at login», тумблер и текущий
статус текстом. Статус хранится в `PopoverModel` как `LoginItemStatus?` с начальным `nil` и
читается ровно двумя вызывающими — `popoverDidOpen()` и `setLaunchAtLogin(_:)`. Кодовая
половина TASK-008 не тронута; два файла, 230 добавленных строк.

**Дополнение после ревью (2026-08-29).** По эскалации из этого же отчёта закрыт пробел в
логировании: оба catch-блока `setLaunchAtLogin(_:)` теперь пишут строку в категорию
`loginitem`. Расхождение было в **пакете** («всё остальное сервис пишет сам»), не в карточке;
`LoginItemService` при этом не тронут, строки живут в разрешённой зоне. Все четыре проверки
перепрогнаны после правки.

**Измерение `.onAppear` снять не удалось**: оно требует физического нажатия на пункт меню-бара,
а синтетический клик невозможен без интерактивного грант-диалога Accessibility (см. «Не
запускалось»). Стоп-условие 5 из-за этого не оценено — ни подтверждено, ни опровергнуто.

В настоящий `~/Library/LaunchAgents` за всё исполнение ничего не записано; переключатель не
нажимался.

## Изменённые файлы

| Файл | Что изменено |
|---|---|
| `Sources/Terminator/PopoverModel.swift` | второй `Logger` с категорией `loginitem`; поправлен комментарий у `popoverLog`, утверждавший, что новых категорий не заводится; `private let loginItem = LoginItemService()`; `loginItemStatus: LoginItemStatus?` и `loginItemRegistrationPending`; вычисляемые `launchAtLoginIsOn` / `launchAtLoginIsInteractive`; чистая `gesture(for:turningOn:)`; действие `setLaunchAtLogin(_:)` с тремя лог-строками отказа; единственный вызов `status()` в `readLoginItemStatus(registrationWritten:)`; вызов чтения в `popoverDidOpen()` |
| `Sources/Terminator/PopoverView.swift` | `LaunchAtLoginRow` — подпись, тумблер, текст статуса; одна вставка `LaunchAtLoginRow(model: model)` между `Divider()` и `HStack` с кнопками |

Ни один файл кодовой половины TASK-008 не изменён. Ни один файл TASK-006 за пределами двух
разрешённых вставок не изменён.

## Изменения поведения

**Строка.** Ниже `Divider()`, над кнопками «Add App…» / «Quit Terminator»: `Toggle` со стилем
`.switch` и подписью «Launch at login», под ним — строка статуса текстом (`.caption`,
`.secondary`). Текст есть **во всех** состояниях, а не только в проблемных.

**Таблица тумблера** — реализована ровно в трёх местах: `launchAtLoginIsOn` (положение),
`launchAtLoginIsInteractive` (интерактивность), `gesture(for:turningOn:)` (что делает нажатие).

| Статус | Тумблер | Интерактивен | Текст |
|---|---|---|---|
| `nil` (не читали) | выкл | нет | `status not read yet` |
| `.enabled` | вкл | да → `disable()` | `on` |
| `.notRegistered` | выкл | да → `enable(executableAt:)` | `off` |
| `.disabledByUser` | **вкл** | да → **только `disable()`** | `turned off in System Settings › General › Login Items — turn it back on there` |
| `.unknown(rawValue:)` | выкл | нет | `unknown state (system status N)` |

**Главное свойство — путь из `.disabledByUser` в `enable()` отсутствует по конструкции.**
Единственный вызов `enable(executableAt:)` стоит под `case .register`, а `.register`
возвращается ровно из одной ветки:

```swift
switch status {
case .unknown:        return .ignore
case .notRegistered:  return turningOn ? .register : .ignore
case .enabled, .disabledByUser: return turningOn ? .ignore : .unregister
}
```

Из `.disabledByUser` `.register` не возвращается ни при каком значении `turningOn`, а `nil` и
`.unknown` дают `.ignore` до всякой проверки. Switch над доменным перечислением исчерпывающий:
новый случай `LoginItemStatus` сломает сборку, а не тихо провалится в «включить».

**Чтение статуса.** `loginItem.status()` вызывается в одном месте — приватном
`readLoginItemStatus(registrationWritten:)`. У него четыре вызывающих: `popoverDidOpen()` и три
взаимоисключающие ветки `setLaunchAtLogin(_:)` (успех записи, отказ записи, снятие
регистрации). То есть одно открытие поповера = одно чтение = одна строка в логе; одно
переключение = одно чтение. В `body`, в вычисляемых свойствах, в `init` и по таймеру статус не
читается.

**После включения.** Флаг `loginItemRegistrationPending` ставится **только** когда `enable` не
бросил, а перечитанный статус не стал `.enabled`; строка тогда говорит
`registered — takes effect at the next login`. Это не отказ и не оранжевый `notice`. Любое
следующее чтение флаг снимает.

**Отказы.** Пользователю — существующей строкой `notice` поповера (DEC-004, второго
пользовательского канала нет); в лог — отдельной строкой, категория `loginitem`, уровень
`.notice`, `privacy: .public` на каждой интерполяции. Три случая, три пары:

| Случай | `notice` | Лог-строка |
|---|---|---|
| `Bundle.main.executableURL == nil` | `Launch at login was not turned on: this build has no executable path.` | `login item not written: Bundle.main.executableURL is nil` |
| бросок из `enable` | `Launch at login was not turned on. The login item was not written.` | `login item not written: executable=… reason=…` |
| бросок из `disable` | `Launch at login was not turned off. The login item file is still there.` | `login item not removed: path=… reason=…` |

Почему лог, а не только `notice`: `notice` живёт до следующего действия пользователя и
исчезает вместе с поповером, а лог — единственный ответ на вопрос «почему автозапуск не
сработал» (DEC-004, findings §14). Сервис эти три случая не покрывает: `enable` логирует
только отказ генератора plist, а броски из `createDirectory` и `writeDurably` отдаёт молча;
`disable` логирует успех и `fileNoSuchFile`, а любой другой отказ `removeItem` — тоже молча.
Правка сделана в `PopoverModel`, `LoginItemService` не тронут.

`executableURL` силой не разворачивается. `.ignore`-жест `notice` не трогает: иначе исчезла бы
обратная связь прошлого действия.

## Доказательства валидации

Все четыре команды перепрогнаны **после** правки логирования; ниже — вывод этого, последнего
прогона.

| Команда | Результат | Вывод |
|---|---|---|
| `swift build` | успех | `Build complete! (1.55s)` |
| `swift build 2>&1 \| grep -c 'warning:'` | `0` | ноль предупреждений |
| `swift test` | успех | `✔ Test run with 64 tests in 7 suites passed after 0.098 seconds.` — 64 теста, новых не добавлялось |
| `scripts/check-forbidden.sh` | exit 0 | `OK:    запрещённых конструкций не найдено` |
| `./build.sh` | exit 0 | см. лог ниже; терминальный шаг `codesign --verify --strict` прошёл |
| `codesign --verify --strict --verbose=2 build/Terminator.app` | exit 0 | `valid on disk` / `satisfies its Designated Requirement` |

`./build.sh` дословно:

```
--- swift build -c debug ---
[0/1] Planning build
Building for debugging...
[0/3] Write swift-version--58304C5D6DBC2206.txt
Build complete! (0.11s)
--- assemble build/Terminator.app ---
--- codesign --force --sign "Terminator Dev" (последняя мутация бандла) ---
build/Terminator.app: replacing existing signature
--- designated requirement guard ---
designated requirement: identifier "com.svvoff.terminator" and certificate leaf = H"74d582911cd0b2c7ff3961af4bb0561efd6a8f24"
--- codesign --verify --strict (терминальный шаг) ---
build.sh exit=0
```

Греп-гейт критерия 8 (эти четыре строки `check-forbidden.sh` не проверяет):

```
$ git diff -U0 -- Sources/ scripts/ Package.swift Packaging/ build.sh \
    | grep -nE 'launchctl|SMAppService\.mainApp|loginItem\(identifier:|KeepAlive' || echo clean
clean
```

Полный `git diff -U0` даёт срабатывания, но **все** они — из
`docs/ai/handoff/current-task-packet-loginitem.md`, который переписал оркестратор перед
запуском: это текст самого пакета (его «Не-цели», формулировка критерия 8 и сама команда
внутри блока кода). Ни одно срабатывание не в коде, что и показывает греп выше, ограниченный
кодовыми путями.

Места вызова статуса (критерий 2):

```
$ grep -rn "readLoginItemStatus\|loginItem\.status()" Sources/Terminator/
Sources/Terminator/PopoverModel.swift:124:        readLoginItemStatus()
Sources/Terminator/PopoverModel.swift:216:                readLoginItemStatus(registrationWritten: true)
Sources/Terminator/PopoverModel.swift:225:                readLoginItemStatus()
Sources/Terminator/PopoverModel.swift:239:            readLoginItemStatus()
Sources/Terminator/PopoverModel.swift:248:    private func readLoginItemStatus(registrationWritten: Bool = false) {
Sources/Terminator/PopoverModel.swift:249:        let status = loginItem.status()
```

Строка 124 — тело `popoverDidOpen()`. Строки 216/225/239 — три взаимоисключающие ветки
`setLaunchAtLogin(_:)`. Строка 249 — единственное вхождение `status()` во всём приложении.

Все лог-строки поповера и их аннотации приватности:

```
$ grep -n "loginItemLog.notice\|popoverLog.notice" Sources/Terminator/PopoverModel.swift
125:  popoverLog.notice("popover opened with quarantined store, …: reason=\(reason, privacy: .public)")
211:  loginItemLog.notice("login item not written: Bundle.main.executableURL is nil")
223:  loginItemLog.notice("login item not written: executable=\(executable.path, privacy: .public) reason=\(reason, privacy: .public)")
236:  loginItemLog.notice("login item not removed: path=\(self.loginItem.plistURL.path, privacy: .public) reason=\(reason, privacy: .public)")
282:  popoverLog.notice("rule not created, bundle has no identifier: path=\(url.path, privacy: .public)")
399:  popoverLog.notice("edit refused: bundle=\(bundleIdentifier, privacy: .public) reason=\(reason, privacy: .public)")

$ grep -n "Log.notice(" Sources/Terminator/PopoverModel.swift | grep '\\(' | grep -v 'privacy: .public'
none
```

Уровень у всех шести — `.notice`; подсистема одна, `TerminatorLog.subsystem`; ни одной
интерполяции без `privacy: .public`. Строка 211 интерполяций не содержит вовсе.

`~/Library/LaunchAgents` — до и после исполнения, без публикации состава:

```
=== до ===
drwxr-xr-x  4 as.sorokin  staff  128 Jun 18 18:29 /Users/as.sorokin/Library/LaunchAgents
       2
test -f ~/Library/LaunchAgents/com.svvoff.terminator.plist; echo $?  →  1

=== после ===
drwxr-xr-x  4 as.sorokin  staff  128 Jun 18 18:29 /Users/as.sorokin/Library/LaunchAgents
       2
test -f ~/Library/LaunchAgents/com.svvoff.terminator.plist; echo $?  →  1
```

Та же mtime каталога (`Jun 18 18:29`), то же число файлов (2), нашего plist нет в обоих
прогонах. Ни один чужой агент не открывался: снималась только метадата каталога.

## Acceptance criteria

| Критерий | Статус | Чем подтверждён |
|---|---|---|
| 1. Строка ниже `Divider()` с подписью, тумблером и статусом текстом | выполнен | `PopoverView.swift`: вставка `LaunchAtLoginRow(model: model)` сразу после `Divider()`; в самой строке `Toggle("Launch at login", …)` и `Text(statusText)`. Текст присутствует во всех пяти состояниях |
| 2. `status()` только при открытии и после переключения | выполнен | греп выше: одно вхождение `loginItem.status()`, четыре вызывающих у обёртки, все перечислены. Ни в `body`, ни в вычисляемом свойстве, ни в `init`, ни по таймеру |
| 3. `LoginItemStatus?` с начальным `nil`, до чтения строка это показывает, тумблер неинтерактивен | выполнен | `private(set) var loginItemStatus: LoginItemStatus?` без инициализатора; `launchAtLoginIsInteractive` возвращает `false` на `nil`; `statusText` даёт `status not read yet` |
| 4. Таблица тумблера в пяти строках; из `.disabledByUser` нет пути в `enable` | выполнен | таблица в «Изменениях поведения»; `gesture(for:turningOn:)` возвращает `.register` только из `.notRegistered`, а `enable(executableAt:)` вызывается только под `case .register` |
| 5. `.unknown(rawValue:)` показан как неизвестное с сырым числом, контрол неинтерактивен | выполнен | `statusText` → `unknown state (system status \(rawValue))`; `launchAtLoginIsInteractive` = `false`; `launchAtLoginIsOn` = `false` — не приравнен ни к вкл, ни к выкл, потому что тумблер в нём выключен и заблокирован |
| 6. После переключения строка из перечитанного `status()`; успешная запись без `.enabled` → «вступит в силу при следующем входе» | выполнен | `readLoginItemStatus(registrationWritten:)` всегда перечитывает; `loginItemRegistrationPending = registrationWritten && status != .enabled`; текст `registered — takes effect at the next login` идёт раньше switch и мимо `notice` |
| 7. Ошибки, включая `nil` у `executableURL`, показаны строкой `notice` | выполнен | три присваивания `notice` в `setLaunchAtLogin(_:)`, таблица в «Изменениях поведения»; те же три случая пишут по строке в категорию `loginitem` — греп лог-строк выше |
| 8. `launchctl`, `SMAppService.mainApp`, `loginItem(identifier:`, `KeepAlive` не встречаются | выполнен | греп-гейт выше: `clean` по кодовым путям; срабатывания только в тексте пакета |
| 9. Файлы кодовой половины TASK-008 не изменены | выполнен | `git status --short -- Sources/TerminatorAppKit/LoginItemService.swift Sources/TerminatorCore/LoginItem.swift Tests/TerminatorCoreTests/LoginItemTests.swift` — пусто; `git diff --stat -- Sources/` показывает только два файла поповера |
| 10. В `~/Library/LaunchAgents` ничего не записано | выполнен | замер до и после выше: та же mtime, то же число файлов, `1` в обоих прогонах |

`git diff --stat -- Sources/`:

```
 Sources/Terminator/PopoverModel.swift | 170 +++++++++++++++++++++++++++++++++-
 Sources/Terminator/PopoverView.swift  |  62 +++++++++++++
 2 files changed, 230 insertions(+), 2 deletions(-)
```

## Не запускалось

### Измерение `.onAppear` — не снято, требует человека

Пакет просит собрать бандл, открыть и закрыть поповер трижды и посчитать строки
`login item status:`. **Первую половину выполнить нечем.** `MenuBarExtra` стиля `.window` не
даёт программного способа открыть поповер: `NSStatusItem` наружу не выставлен, а
синтетический клик по пункту меню-бара (`System Events`, `CGEventPost`, `cliclick`) требует
гранта Accessibility вызывающему процессу, то есть интерактивного диалога согласия. EXECUTOR
это запрещает прямо: «диалоги согласия интерактивны: любой путь, который их вызывает, требует
человека за клавиатурой. Останавливайся и сообщай». Головой и руками агента измерение
недостижимо; головой и руками автора — тридцать секунд.

Проверил, нет ли уже готового доказательства в логе, — нет:

```
$ log show --predicate 'subsystem == "com.svvoff.terminator"' --style compact --last 3h | grep -c "login item status:"
0
```

(лог за 3 часа пуст целиком: `popoverDidOpen()` до этой правки писал строку только при
карантине хранилища, а движок логирует лишь свои шесть событий. Косвенного следа срабатываний
`.onAppear` в продукте сегодня не существует.)

**Что должен сделать человек** — после запуска пересобранного бандла:

1. `./build.sh && ./build/Terminator.app/Contents/MacOS/Terminator`
   (важно: сейчас в системе живёт процесс pid 30917 с **прежним** бинарём — бандл на диске
   пересобран под ним, но образ у запущенного процесса старый и строки автозапуска в нём нет.
   Его надо закрыть кнопкой «Quit Terminator» и запустить заново);
2. открыть и закрыть поповер **трижды**;
3. `log show --predicate 'subsystem == "com.svvoff.terminator"' --style compact --last 10m | grep -c "login item status:"`

Ожидается **3**. **1** — это стоп-условие 5: детекция открытия живёт в `TerminatorApp.swift`,
это запрещённая зона, и чинить её здесь нельзя. Стоп-условие 5 сейчас **не оценено**.

Побочно: в `~/Library/Application Support/com.svvoff.terminator/config.json` лежит одно
правило (`com.apple.TextEdit`) **без** `enabledAt`, то есть выключенное. Перезапуск продукта
для этого измерения ничего ни у кого не закроет.

### Ручной чеклист — не засчитываю

`validation_profile: [manual-checklist]`. Шесть подпунктов критерия 5 карточки выполняет автор
на своей машине; исполнителем они не засчитываются и не имитируются:

1. включить автозапуск в поповере и убедиться, что появился
   `~/Library/LaunchAgents/com.svvoff.terminator.plist`, а `plutil -lint` на нём проходит;
2. заметить разовое системное уведомление «Background items added» (ожидаемо, DEC-004 не
   нарушает);
3. перезагрузиться или выйти и войти заново и увидеть Terminator в меню-баре;
4. выключить пункт в System Settings → General → Login Items;
5. открыть поповер и убедиться, что продукт сообщает изменённое состояние
   (`disabledByUser`-случай, а не отказ), — и записать, **что именно** вернула система;
6. пересобрать приложение и убедиться, что регистрация всё ещё указывает на живой путь и
   работает.

**Первая настоящая запись plist произойдёт на подпункте 1, руками автора.** За всё исполнение
этого раунда переключатель не нажимался ни разу — ни руками, ни кодом, ни «чтобы проверить».

Отдельно к подпункту 5: карточка требует записать в журнал, сообщает ли `statusForLegacyPlist`
включённое состояние сразу после записи файла или только после следующего входа. Оба прочтения
у строки нормальны: сразу — `on`, не сразу — `registered — takes effect at the next login`.
Различить «не записалось» и «записалось, но статус не догнал» есть чем: сервис пишет отдельную
строку `login item written: path=… executable=… bytes=…`.

Отдельного файла чеклиста не создавал: нумерованный чеклист живёт в самой карточке.

### Юнит-тесты не добавлялись

Раунд их не требует: чистые части покрыты пятью тестами раунда 1, а тумблер SwiftUI юнит-тестом
не проверяется. Тестовый таргет зависит только от `TerminatorCore` и `PopoverModel` не видит.

## Проверка скоупа

```
$ git status --short
 M Sources/Terminator/PopoverModel.swift
 M Sources/Terminator/PopoverView.swift
 M docs/ai/handoff/current-execution-report-loginitem.md  (этот отчёт, поверх раунда 1)
 M docs/ai/handoff/current-task-packet-loginitem.md       (правка оркестратора, не моя)
```

Запрещённые зоны не тронуты:

- **Кодовая половина TASK-008** — `LoginItemService.swift`, `LoginItem.swift`,
  `LoginItemTests.swift`: не изменены (пустой `git status` по этим трём путям), не
  рефакторились, не читались «на предмет улучшений» — только на предмет API, который я зову;
- **TASK-006** — правок ровно две разрешённые: вставка строки в `PopoverView.swift` и её
  действие плюс хранение статуса в `PopoverModel.swift`. Вью-модель ядра, её тесты, логика
  отсчёта, порядок строк, баннер карантина, предикат глаз, пути добавления и удаления правил
  не тронуты. Отдельно: поправлен комментарий у `popoverLog`, утверждавший «новых категорий
  эта карточка не заводит», — пакет это разрешает явно и единственным исключением;
- `TerminatorApp.swift`, `WatchController.swift`, движок, путь quit, Apple Events, модель
  правил, схема конфига — не тронуты;
- `Info.plist`, `build.sh`, подпись, keychain, `Package.swift` — не тронуты;
- **настоящий `~/Library/LaunchAgents`** — ни записи, ни чтения содержимого чужих агентов;
  снималась только метадата каталога (`ls -ld`, `ls | wc -l`, `test -f`). Имена чужих агентов
  в отчёт не переписаны;
- ни одного `swiftLanguageMode(.v5)`, `@preconcurrency`, `@unchecked Sendable`,
  `UserDefaults`, `Bundle.module`, `swift run` — подтверждено `check-forbidden.sh`;
- `launchctl`, `SMAppService.mainApp`, `SMAppService.loginItem(identifier:)`, `KeepAlive` — в
  коде отсутствуют.

## Риски

1. **`.onAppear` может сработать один раз за жизнь сцены.** Не измерено, и это главный
   остаточный риск: тогда статус читается только при первом открытии, и изменение,
   сделанное пользователем в System Settings между открытиями, строка не покажет до
   перезапуска. Тем же хуком висит `reloadFromDisk()` из TASK-006, так что риск не мой и не
   новый — но моя строка делает его видимым. Чинить нечем: детекция открытия в
   `TerminatorApp.swift`, запрещённая зона.
2. **Текст `disabledByUser` длинный** (одна фраза с путём в System Settings) и на 340pt
   ширины займёт две строки. Проверено только чтением кода: `fixedSize(horizontal: false,
   vertical: true)` перенос разрешает, обрезки быть не должно. Глазами не смотрел — поповер
   открыть нечем.
3. **`.notRegistered` сразу после успешной записи нарисует выключенный тумблер** при
   пояснительном тексте «registered — takes effect at the next login». Это прямое следствие
   таблицы пакета (тумблер — функция статуса, и только его), а не отсебятина; выглядит
   странно ровно в том случае, который карточка называет неизмеренным. Подпункт 1 чеклиста
   покажет, случается ли он вообще.

## Незавершённое и follow-up

- **Измерение `.onAppear`** — снять человеком по трём шагам выше. От результата зависит,
  срабатывает ли стоп-условие 5.
- **Ручной чеклист TASK-008**, шесть подпунктов, — на авторе. Первая настоящая запись plist
  там же.
- **Кандидат в ядро с тестами:** `PopoverModel.gesture(for:turningOn:)` — чистая функция
  `(LoginItemStatus?, Bool) -> …`, целиком выражающая таблицу из пакета, включая свойство
  «из `.disabledByUser` нет пути в `enable`». Сейчас она приватная в UI-слое и не покрыта
  тестом; вынесенная в `TerminatorCore`, она проверялась бы восемью строками теста
  (пять состояний × два направления). Скоуп молча не расширял — решение оркестраторское.
- **Закрыто по ходу ревью:** молчаливый отказ записи и удаления. Ревью подтвердило факт
  (`enable` не логирует броски из `createDirectory` и `writeDurably`, `disable` — ничего,
  кроме `fileNoSuchFile`) и распорядилось закрыть пробел в поповере: две строки
  `loginItemLog.notice` в catch-блоках `setLaunchAtLogin(_:)`. Расхождение было в тексте
  пакета («всё остальное сервис пишет сам»), карточка TASK-008 ему не противоречит.
  `LoginItemService` не тронут — принятая кодовая половина не переоткрывалась.
  Проверки после правки перепрогнаны все четыре.


---

# Отчёт об исполнении — inline, раунд 3 (оркестратор)

**Исполнитель: оркестратор, inline.** Субагент не поднимался. Маршрут выбран по третьей оси
`execution-policy.md` — цена проверки: состояние `disabledByUser` было живым на машине автора в
момент находки и исчезло бы к тому времени, когда был бы написан и исполнен пакет. Политика
такой маршрут допускает при двух условиях, оба выполнены: отчёт написан (этот файл) и ревью
проведено **отдельным ходом** по реальному диффу.

## Что чинилось

Дефект, найденный подпунктом 5 ручного чеклиста: строка автозапуска в состоянии
`disabledByUser` после щелчка тумблера показывала «registered — takes effect at the next login»
вместо правильного текста про System Settings. Разбор и обоснование — амендмент 2 карточки
TASK-008.

## Дифф

```
 Sources/Terminator/PopoverModel.swift          | 21 ++++++++++++++-------
 Sources/TerminatorCore/LoginItem.swift         | 24 ++++++++++++++++++++++++
 Tests/TerminatorCoreTests/LoginItemTests.swift | 19 +++++++++++++++++++
 3 files changed, 57 insertions(+), 7 deletions(-)
```

Содержательных строк три:

```swift
-        loginItemRegistrationPending = registrationWritten && status != .enabled
+        loginItemRegistrationPending = registrationWritten && status.registrationCanTakeEffect

+    public var registrationCanTakeEffect: Bool {
+        switch self {
+        case .enabled, .disabledByUser: false
+        case .notRegistered, .unknown: true
+        }
+    }
```

Решение вынесено в `TerminatorCore` намеренно: в app-таргете юнит-тестов нет по конструкции, а
acceptance criteria TASK-006 требует, чтобы логика представления жила в ядре и проверялась там.

Остальные строки диффа в `PopoverModel.swift` — **документация**, приведённая в соответствие с
новым поведением по замечанию ревью: прежние комментарии над `loginItemRegistrationPending` и
`readLoginItemStatus` описывали снятый инвариант «любая успешная запись плюс не-`.enabled` даёт
обещание следующего входа». Кода они не меняют, но расходящийся с кодом комментарий — тот же
дефект, только читаемый человеком.

## Доказательства

| Проверка | Результат |
|---|---|
| `swift build` | зелёный, **0** строк `warning:` |
| `swift build -c release` | зелёный, **0** строк `warning:` |
| `swift test` | **83 теста в 8 сьютах**, exit=0, 0.098 с |
| `scripts/check-forbidden.sh` | `OK: запрещённых конструкций не найдено` |
| `scripts/verify-docs.sh` | 0 ошибок, 0 предупреждений |
| `./build.sh` | EXIT=0, `codesign --verify --strict` терминальным шагом |
| designated requirement | совпал дословно с эталоном |

Сборка делалась на **чистом дереве** — `.build` удалён перед первым прогоном.

## Мутационный опыт

Тест мог бы оказаться пустым — он проверяет свойство, которого до правки не существовало.
Предикат временно возвращён к прежнему поведению (`disabledByUser` → `true`):

```
✘ Test disabledByUserNeverPromisesTheNextLogin() recorded an issue at LoginItemTests.swift:51:9:
  Expectation failed: (LoginItemStatus.disabledByUser.registrationCanTakeEffect → true) == false
✘ Test run with 83 tests in 8 suites failed after 0.099 seconds with 1 issue.
```

Упал ровно один тест и ровно на том ожидании, ради которого написан. После восстановления —
83/83 зелёные.

## Ревью оркестратора — отдельным ходом

Смотрелся реальный дифф, не пересказ.

- **Изменился ровно один случай.** Прежнее `status != .enabled` давало `true` для
  `notRegistered`, `unknown` и `disabledByUser`; новое отличается только последним. Остальные
  пути не тронуты, включая обещание для переходного `unknown(3)`.
- **Switch исчерпывающий, без `default:`** — новый case в enum сломает сборку, а не унаследует
  молча «может вступить». Это то же свойство, которым защищён маппинг сырых статусов.
- **Ядро осталось чистым:** Foundation only, ни AppKit, ни часов, ни ввода-вывода.
- **Новых строк лога нет**, поэтому требование `privacy: .public` не затронуто; проверено
  отдельно, что в изменённом файле все интерполяции его несут.
- `gesture(for:)` и гарантия «из `.disabledByUser` никогда не `.register`» не тронуты — они и
  были правильными.

**Вердикт: ACCEPT.**

## Что осталось непроверенным руками

Живое подтверждение починки глазами автор не делал: к тому моменту состояние вернули в
`enabled`, а повторный круг стоил бы ещё одного выключения в System Settings. Дефект покрыт
тестом, проверенным мутацией, и это записано как сознательный выбор, а не как упущение.
