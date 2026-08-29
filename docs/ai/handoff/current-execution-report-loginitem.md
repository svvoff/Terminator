# Отчёт об исполнении

Поток `loginitem`. Пакет — `docs/ai/handoff/current-task-packet-loginitem.md`.

## Задача

TASK-008 — автозапуск через рукописный plist в `~/Library/LaunchAgents`.

## Кратко

Добавлены три файла: чистый генератор plist и чистое отображение статуса в ядре, адаптер с
записью/удалением/чтением статуса через `SMAppService.statusForLegacyPlist(at:)`, и пять
тестов в `Tests/TerminatorCoreTests/`. Существующие файлы не менялись — ни один. Настоящий
`~/Library/LaunchAgents` не тронут: ни записи, ни удаления, ни чтения чужих агентов. UI не
трогался (TASK-006 не сделана). Ручной чеклист из шести подпунктов не выполнялся и не
засчитан; отдельного файла чеклиста не создавалось (П1 пакета).

## Изменённые файлы

| Файл | Что изменено |
|---|---|
| `Sources/TerminatorCore/LoginItem.swift` | **новый.** `LoginItemStatus` (4 случая, включая явный `unknown(rawValue:)`), `LoginItemStatus.init(systemStatusRawValue:)` — чистая функция отображения; `LoginItemPlistError`; `LoginItemPlist` — `label`, `fileName`, `data(forExecutableAt:)`. Ввода-вывода нет ни строки. |
| `Sources/TerminatorAppKit/LoginItemService.swift` | **новый.** `loginItemLog` (подсистема продукта, категория `loginitem`); `LoginItemService` — `defaultAgentsDirectory`, `plistURL`, `enable(executableAt:)`, `disable()`, `status()`. |
| `Tests/TerminatorCoreTests/LoginItemTests.swift` | **новый.** Сьют «Автозапуск: содержимое plist и отображение статуса», 5 тестов. |

Ничего больше. `git status --short` показывает ровно три новых файла, добавленных этим
потоком; остальные записи в дереве принадлежат TASK-004 и оркестратору и мной не тронуты.

## Изменения поведения

Граница слоёв — по П3 пакета:

- **Ядро (`TerminatorCore`, только Foundation).** Генератор plist и отображение статуса.
  Исполняемый URL приходит **параметром**, поэтому и то и другое тестируется без бандла,
  без `ServiceManagement` и без файловой системы.
- **Адаптер (`TerminatorAppKit`).** `import ServiceManagement`; запись через `writeDurably`,
  удаление, чтение `SMAppService.statusForLegacyPlist(at:)`. Адаптер передаёт в ядро
  `status.rawValue` — обычный `Int`, который тест умеет построить.

Содержимое plist — ровно три ключа: `Label` = `com.svvoff.terminator`, `ProgramArguments` —
один абсолютный путь к бинарю внутри `.app`, `RunAtLoad` = `true`. Четвёртого ключа нет.

Отказ генератора: URL не файловый → `notAFileURL`; URL не лежит по раскладке
`…/<имя>.app/Contents/MacOS/<файл>` → `executableNotInsideAppBundle`. В обоих случаях на диск
не пишется ничего, а `enable` логирует отказ на `.notice` и пробрасывает ошибку.

Отображение статуса покрывает **три** значения — те, что разведка измерила на реальных
агентах через `statusForLegacyPlist` (findings §12): `notRegistered` (0) → `.notRegistered`,
`enabled` (1) → `.enabled`, `requiresApproval` (2) → `.disabledByUser`. Всё остальное, включая
`notFound` (3), даёт `.unknown(rawValue:)`. Обоснование — прямо из карточки: доменный enum
покрывает три состояния «and an explicit unknown case for any status value not covered»;
`notFound` — never-registered статус **другого** API (`SMAppService.mainApp`), на legacy-пути
не наблюдавшийся, и отобразить его в `.notRegistered` значило бы выдумать измерение. См.
раздел «Риски»: это единственное место, где я выбирал, и выбор дешёво отменить.

`disable()` идемпотентен: отсутствие файла — не отказ. Удаляется ровно `plistURL`.

`status()` ничего не чинит и ничего не перезаписывает. Обнаруженное `disabledByUser`
остаётся как есть — перерегистрация за спиной пользователя запрещена DEC-006.

Сервис ни к чему не подключён: попапа нет, TASK-006 не сделана, UI по пакету не трогается.
Ни один вызов `enable`/`disable`/`status` в дереве не существует.

## Доказательства валидации

| Команда | Результат | Вывод |
|---|---|---|
| `swift build` | EXIT=0, `warning:` — **0 строк** | см. ниже |
| `swift build -c release` | EXIT=0, `warning:` — **0 строк** | см. ниже |
| `swift test` | EXIT=0, **50 тестов в 6 сьютах**, `warning:` — 0 | см. ниже |
| `swift test -c release` | EXIT=0, **50 тестов в 6 сьютах**, `warning:` — 0 | см. ниже |
| `scripts/check-forbidden.sh` | EXIT=0 | `OK:    запрещённых конструкций не найдено` |
| `./build.sh` | EXIT=0, терминальный шаг `codesign --verify --strict` | см. ниже |

Базовая линия до правки замерена в этом же дереве: `swift test` → `Test run with 45 tests in
5 suites passed`. Стало 50 в 6 — добавлено пять, ни один существующий тест не менялся и не
удалялся (в `Tests/` изменён ноль существующих файлов).

### `swift build` (после `rm -rf .build`, полная пересборка)

```
$ swift build ; echo EXIT=$?
...
[33/36] Emitting module Terminator
[33/36] Write Objects.LinkFileList
[34/36] Linking Terminator
[35/36] Applying Terminator
Build complete! (9.75s)
EXIT=0
$ grep -c 'warning:' build-debug.txt
0
```

### `swift build -c release`

```
$ swift build -c release ; echo EXIT=$?
[6/8] Compiling TerminatorAppKit EngineLogRenderer.swift
[7/9] Compiling Terminator PlaceholderView.swift
[7/9] Write Objects.LinkFileList
[8/9] Linking Terminator
Build complete! (6.61s)
EXIT=0
warnings: 0
```

### `swift test`

```
$ swift test ; echo EXIT=$?
...
✔ Test generatorRefusesAnythingOutsideAnAppBundle() passed after 0.072 seconds.
✔ Test statusMappingSurfacesEverythingItDoesNotKnow() passed after 0.071 seconds.
✔ Test generatedPlistCarriesExactlyThreeKeys() passed after 0.071 seconds.
✔ Test generatedPlistRoundTripsThroughPropertyListSerialization() passed after 0.071 seconds.
✔ Test durablyWrittenPlistParsesBackFromDisk() passed after 0.077 seconds.
✔ Suite "Автозапуск: содержимое plist и отображение статуса" passed after 0.078 seconds.
✔ Test run with 50 tests in 6 suites passed after 0.107 seconds.
EXIT=0
warnings: 0
```

### `swift test -c release`

```
$ swift test -c release ; echo EXIT=$?
✔ Test run with 50 tests in 6 suites passed after 0.102 seconds.
EXIT=0
warnings: 0
```

### `scripts/check-forbidden.sh`

```
$ scripts/check-forbidden.sh ; echo EXIT=$?
OK:    запрещённых конструкций не найдено
EXIT=0
```

### `./build.sh`

```
$ ./build.sh ; echo EXIT=$?
--- swift build -c debug ---
Build complete! (0.13s)
--- assemble build/Terminator.app ---
--- codesign --force --sign "Terminator Dev" (последняя мутация бандла) ---
build/Terminator.app: replacing existing signature
--- designated requirement guard ---
designated requirement: identifier "com.svvoff.terminator" and certificate leaf = H"74d582911cd0b2c7ff3961af4bb0561efd6a8f24"
--- codesign --verify --strict (терминальный шаг) ---
EXIT=0
```

### Что реально порождает генератор

Скретч-бинарь, слинкованный с объектниками `TerminatorCore` **вне репозитория**, позвал
`LoginItemPlist.data(forExecutableAt:)` для настоящего пути бандла:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.svvoff.terminator</string>
	<key>ProgramArguments</key>
	<array>
		<string>/Users/as.sorokin/Developer/own/terminator/build/Terminator.app/Contents/MacOS/Terminator</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
```

Записан в скретчпад (**не** в `~/Library/LaunchAgents`) и проверен:

```
$ plutil -lint .../scratchpad/com.svvoff.terminator.plist ; echo EXIT=$?
.../scratchpad/com.svvoff.terminator.plist: OK
EXIT=0
```

Это заранее снимает риск по подпункту 1 ручного чеклиста: `plutil -lint` на форме, которую
порождает продукт, проходит. Сам подпункт остаётся за человеком — он про файл в настоящем
каталоге и про регистрацию.

### `privacy: .public` — построчно

Лог-строк добавлено пять, все в `Sources/TerminatorAppKit/LoginItemService.swift`, все на
`.notice`, все на подсистеме `TerminatorLog.subsystem` и категории
`TerminatorLog.Category.loginItem` (новых категорий не заводилось — список закрытый).

| Строка | Интерполяции | `privacy: .public` |
|---|---|---|
| 97 `login item refused, nothing written:` | `executable.path`, `reason` | обе |
| 106 `login item written:` | `self.plistURL.path`, `executable.path`, `bytes.count` | все три |
| 117 `login item removed:` | `self.plistURL.path` | есть |
| 119 `login item already absent:` | `self.plistURL.path` | есть |
| 138 `login item status:` | `self.plistURL.path`, `system.rawValue`, `described` | все три |

Механическая проверка — все интерполяции файла минус те, что несут `privacy: .public`:

```
$ grep -no '\\([^)]*)' Sources/TerminatorAppKit/LoginItemService.swift | grep -v 'privacy: .public'
(none)
```

## Acceptance criteria

| Критерий | Статус | Чем подтверждён |
|---|---|---|
| 1. Отображение статуса — чистая функция; необработанное значение даёт явное «неизвестно», а не падение и не молчаливое «включено» | выполнен | `statusMappingSurfacesEverythingItDoesNotKnow()`. Проверяет 0/1/2 → `.notRegistered`/`.enabled`/`.disabledByUser`; 3, 4, 99, −1 → `.unknown(rawValue:)`; и отдельным циклом — что **ни одно** значение из −5…20, кроме единственного измеренного 1, не отображается в `.enabled`. Функция живёт в ядре и `ServiceManagement` не требует. |
| 2. Содержимое plist: `Label`, один абсолютный путь на `Terminator.app/Contents/MacOS/Terminator`, `RunAtLoad` = `true`, других ключей нет, `KeepAlive` отсутствует | выполнен | `generatedPlistCarriesExactlyThreeKeys()`: `keys.sorted() == ["Label","ProgramArguments","RunAtLoad"]`, отдельная строка на отсутствие ключа воскрешения, `arguments.count == 1`, префикс `/`, суффикс `Terminator.app/Contents/MacOS/Terminator`, плюс проверка, что `RunAtLoad` сериализовался тегом `<true/>`, а не числом. Форма подтверждена дампом выше. |
| 3. Данные разбираются как property list | выполнен | `generatedPlistRoundTripsThroughPropertyListSerialization()`: round-trip через `PropertyListSerialization.propertyList(from:options:format:)`, формат на выходе `.xml`, поля сходятся. Плюс `durablyWrittenPlistParsesBackFromDisk()` — round-trip уже с диска, после `writeDurably`. Плюс `plutil -lint` выше. |
| 4. Отказ для URL вне `.app`-бандла | выполнен | `generatorRefusesAnythingOutsideAnAppBundle()`: семь путей (в т.ч. настоящий продукт `swift build` — `.build/debug/Terminator`, и три «почти похожих»: `.app/Terminator`, `.app/Contents/Terminator`, `.app/Contents/MacOS/nested/Terminator`) → `executableNotInsideAppBundle`; не-файловый URL → `notAFileURL`. Ошибка сравнивается **по значению**, а не по типу. |
| 5. Ручной чеклист из шести подпунктов | **требует человека** | Не выполнялся и **не засчитан**. Отдельного файла чеклиста не создавалось — П1 пакета. Подпункты и что с ними делать — ниже. |

## Не запускалось

### Критерий 5 — ручной чеклист. Выполняет автор, на своей машине

Пакет: **после пункта 8 чеклиста TASK-004** — подпункт 3 требует перезагрузки, а она убьёт
идущее измерение соседнего потока.

Ничего из этого не имеет headless-эквивалента, и подменять его я не пробовал. Сервис к UI не
подключён, поэтому включение/выключение сегодня возможно только из кода — на момент прогона
чеклиста понадобится либо строка в поповере (TASK-006), либо разовый вызов, который решает
оркестратор. Это и есть главное незавершённое (см. follow-up).

1. **Включить автозапуск и убедиться, что plist появился.** Что делает человек: вызывает
   `enable(executableAt: Bundle.main.executableURL!)` и проверяет
   `ls -la ~/Library/LaunchAgents/com.svvoff.terminator.plist`, затем
   `plutil -lint ~/Library/LaunchAgents/com.svvoff.terminator.plist`.
   На что смотреть: файл ровно один и назван точно так; `plutil` печатает `OK`; внутри —
   три ключа и абсолютный путь к бинарю **внутри `build/Terminator.app`**, а не к продукту
   `swift build`. Два чужих агента (`com.valvesoftware.steamclean.plist`,
   `homebrew.mxcl.dnsmasq.plist`) остались на месте, с прежними размерами и mtime.
2. **Отметить разовое уведомление «Background items added».** Что делает человек: смотрит на
   экран в момент первой регистрации и записывает, появилось оно или нет.
   На что смотреть: это извещение ОС, оно **ожидаемо** и нарушением DEC-004 не является
   (карточка DEC-004, раздел «Decision», пункт 2). Отсутствие уведомления — тоже факт, его
   стоит записать.
3. **Перезагрузиться (или выйти и войти) и убедиться, что Terminator запущен.** Что делает
   человек: перезагружает машину, после входа смотрит на меню-бар.
   На что смотреть: череп в меню-баре присутствует. Полезно заодно снять
   `log show --predicate 'subsystem == "com.svvoff.terminator"' --style compact --last 1h` —
   там должна быть строка `login item status: … status=…`, если статус читался.
   **Делать только после пункта 8 чеклиста TASK-004.**
4. **Выключить пункт в System Settings → General → Login Items.** Что делает человек:
   открывает панель, находит Terminator, переводит переключатель в off.
   На что смотреть: файл plist при этом **остаётся** на диске — выключение системное, а не
   удаление.
5. **Убедиться, что приложение сообщает изменившееся состояние — случай «выключено
   пользователем», а не ошибку.** Что делает человек: вызывает `status()` и читает лог тем
   же предикатом.
   На что смотреть: в логе `status=disabledByUser` и `systemStatus=2`. Если приехало
   `status=unknown(rawValue: N)` — это **не** падение и не ошибка, это ровно тот сигнал,
   ради которого случай заведён: записать N и принести оркестратору, потому что разведка
   такого значения на legacy-пути не видела.
6. **Пересобрать приложение и убедиться, что регистрация всё ещё указывает на валидный путь
   и всё ещё работает.** Что делает человек: `./build.sh`, затем снова `status()` и,
   в идеале, ещё один вход в систему.
   На что смотреть: содержимое plist не изменилось и путь по-прежнему указывает на
   существующий файл. Это **то самое свойство**, ради которого выбран legacy-plist: он
   ссылается на путь, а не на cdhash (findings §12). Если бы регистрация протухала на
   пересборке — механизм выбран зря, и это повод остановиться, а не чинить на месте.

Отдельно, чего чеклист требует записать в лог исполнения (карточка, «Documentation
updates required»): **сообщает ли `statusForLegacyPlist` включённое состояние сразу после
записи файла или только после следующего входа**. Разведкой это не установлено (П5 пакета),
код относится к обоим прочтениям как к нормальному состоянию, и ответ приносит человек.

### Чего ещё не делалось

- **В настоящий `~/Library/LaunchAgents` не писалось ничего.** Разрешение пользователя по
  зоне 5 ограничено кодом и тестами.
- **UI не трогался.** Строка в поповере разрешена карточкой только при сделанной TASK-006;
  она не сделана.
- `launchctl` в любом виде — не звался и в коде отсутствует.

## Проверка скоупа

**Настоящий `~/Library/LaunchAgents` не тронут.** До и после всех прогонов:

```
$ ls -la ~/Library/LaunchAgents
drwxr-xr-x   4 as.sorokin  staff   128 Jun 18 18:29 .
-rw-r--r--@  1 as.sorokin  staff   878 Apr 30 14:54 com.valvesoftware.steamclean.plist
-rw-r--r--   1 as.sorokin  staff   797 Jun 18 18:29 homebrew.mxcl.dnsmasq.plist
```

Оба чужих агента на месте, размеры и mtime прежние (30 апреля и 18 июня); mtime самого
каталога — 18 июня, то есть в нём ничего не создавалось и не удалялось. Файла
`com.svvoff.terminator.plist` там нет. Ни один чужой агент не открывался на чтение.

**Каким каталогом пользовались тесты.** `withTemporaryDirectory` из
`Tests/TerminatorCoreTests/TemporaryDirectory.swift` (подход TASK-003): `NSTemporaryDirectory()`
= `/var/folders/x5/xk2_kn8x17v4d0jcyndwrf280000gp/T/`, внутри — `terminator-tests-<uuid>/`, а в
нём подкаталог `LaunchAgents/`, созданный самим тестом только ради узнаваемости раскладки.
Каталог убирается в `defer`; после прогонов остатков нет
(`ls -d …/T/terminator-tests-*` → `no matches found`). Четыре теста из пяти файловой системы
не касаются вовсе — генератор и отображение статуса чистые.

Тестовый таргет зависит только от `TerminatorCore`, поэтому дотянуться до
`LoginItemService.defaultAgentsDirectory` он физически не может.

**Уборка временных файлов не расширялась.** `ConfigStore.sweepStrayTemporaryFiles()` не
изменён и по-прежнему ходит только по каталогу данных приложения. В адаптере автозапуска
уборки нет: `writeDurably` убирает свой временный файл сам при ошибке.

**Запрещённые зоны не тронуты.** `git status --short` — этим потоком добавлены ровно три
новых файла:

```
?? Sources/TerminatorCore/LoginItem.swift
?? Sources/TerminatorAppKit/LoginItemService.swift
?? Tests/TerminatorCoreTests/LoginItemTests.swift
```

Изменённых файлов — ноль (`git diff --stat` по моим файлам пуст: они новые). Не тронуты:
`Packaging/Info.plist`, `build.sh`, `Package.swift`, `probes/**`, `scripts/**`,
`docs/product/decisions/**`, `docs/product/recon/macos-findings.md`, файлы TASK-004
(`WatchEngine.swift`, `EngineInput.swift`, `EngineEffect.swift`, `ProcessSession.swift`,
`QuitOutcome.swift`, `ExpiryAction.swift`, `Now.swift`, `ObservedProcess.swift`,
`QuitSender.swift`, `RunningApplicationsObserver.swift`, `WatchController.swift`,
`ProcessLaunchTime.swift`, `EngineLogRenderer.swift`, `WatchEngineTests.swift`),
`Rule.swift`, `RuleConfig.swift`, `ConfigFormat.swift`, `ConfigStore.swift`,
`DurableWrite.swift`, `Sources/Terminator/**`. Файлы соседнего потока
(`current-task-packet.md`, `current-execution-report.md`) не читались и не писались.

**Гейты по не-целям.** Греп по `Sources/` и `Tests/`:

- `KeepAlive` — **одно** вхождение во всём дереве:
  `Tests/TerminatorCoreTests/LoginItemTests.swift:49`,
  `#expect(contents.keys.contains("KeepAlive") == false)`. Строка обязана там быть: критерий 2
  требует «the test asserts `KeepAlive` is absent». В `Sources/` строки нет ни в коде, ни в
  комментариях.
- `launchctl` — одно вхождение, док-комментарий `LoginItemService.swift:35`, в списке того,
  чего сервис не делает и почему. Кода нет.
- `SMAppService.mainApp` — три вхождения, все док-комментарии, все объясняют, почему API не
  используется и что апгрейд принадлежит TASK-105. Кода нет.
- `SMAppService.loginItem(identifier:)` — одно вхождение, док-комментарий
  `LoginItem.swift:6`. Кода нет.

Единственный вызов `SMAppService` во всём дереве — `statusForLegacyPlist(at:)` в
`LoginItemService.status()`.

**Дисциплина ядра.** `Sources/TerminatorCore/LoginItem.swift` импортирует только Foundation;
`ServiceManagement`, `AppKit`, `os` в нём нет. `check-forbidden.sh` (в т.ч. гейты
`import AppKit` / `ContinuousClock` / `DispatchTime` / `protocol Clock` по ядру) — EXIT=0.

## Риски

1. **`notFound` (3) отображён в `.unknown`, а не в `.notRegistered`.** Это единственное
   место, где выбирал я. За `.unknown`: карточка перечисляет ровно три покрытых состояния и
   говорит «explicit unknown case for **any status value not covered**»; разведка на
   legacy-пути измерила три значения, и `notFound` среди них нет — он принадлежит истории
   `SMAppService.mainApp`. Против: если на практике `statusForLegacyPlist` вернёт `notFound`
   для отсутствующего файла, обычное состояние «никогда не включали» будет отрисовываться как
   «неизвестно». Оба прочтения безопасны (в `.enabled` не отображается ни одно значение,
   кроме 1), и подпункт 5 чеклиста ловит это явно: число попадёт в лог как
   `systemStatus=3 status=unknown(rawValue: 3)`. Правка, если оркестратор решит иначе, — одна
   строка в `LoginItemStatus.init`.
2. **Сервис ни к чему не подключён.** Мёртвый код до TASK-006 или до разового вызова.
   Компилятор об этом молчит: тип публичный.
3. **Проверка «внутри `.app`» структурная и строгая** — требует ровно
   `…/<имя>.app/Contents/MacOS/<файл>`. Ровно такую раскладку собирает `build.sh`; другой
   легитимной раскладки у продукта нет. Если она когда-нибудь появится, генератор откажет
   громко (лог на `.notice` + брошенная ошибка), а не запишет мусор.
4. **`enable` и `disable` без юнит-тестов.** Тестовый таргет зависит только от
   `TerminatorCore`, а адаптер живёт в `TerminatorAppKit`; заводить второй тестовый таргет —
   правка `Package.swift`, то есть стоп-условие пакета. Смягчение: вся логика, которую можно
   ошибиться, вынесена в ядро и покрыта; в адаптере остались `createDirectory`,
   `writeDurably`, `removeItem` и один вызов системы. Связка «генератор + `writeDurably` →
   валидный plist на диске» проверена тестом `durablyWrittenPlistParsesBackFromDisk()` во
   временном каталоге.
5. **Побочный эффект прогона:** перед замером чистой сборки я удалил `.build` (артефакт, не
   под гитом). Если соседний поток в этот момент собирался, он просто пересобрался. В
   репозитории следов нет.

## Незавершённое и follow-up

Решает оркестратор — я ничего из этого не открывал.

- **Как автор включит автозапуск на чеклисте.** Публичного вызова нет: UI по пакету не
  трогался. Нужен либо порядок «сначала TASK-006, потом чеклист TASK-008», либо разовый
  способ позвать `enable`/`status` руками. Это блокирует критерий 5, и только его.
- **Результат чеклиста в `execution-log/latest.md`** — включая наблюдённый момент первого
  чтения статуса и точный путь plist (карточка, «Documentation updates required»).
- **Если `statusForLegacyPlist` поведёт себя иначе, чем findings §12** — правка
  `macos-findings.md` принадлежит оркестратору; я findings не трогал.
- `TASK-105` (`SMAppService.mainApp` при Developer ID) здесь не открывался и не упоминается
  нигде, кроме объяснения, почему API не используется сейчас.
