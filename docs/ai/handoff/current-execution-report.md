# Отчёт об исполнении

## Задача

TASK-003 — Rule model and durable config store.

## Кратко

Доменная модель правила (`Rule`, `Limit`, `RuleConfig`), версионированный человекочитаемый
JSON-формат на диске, общий хелпер долговечной записи `writeDurably(_:to:)` и хранилище
`ConfigStore` с читаемым карантином и стартовой уборкой хвостов. Плюс тестовый таргет и
22 синхронных теста, закрывающих 16 из 17 acceptance criteria (17-й — критерий 1 — закрыт
сборкой и грепом).

Пять команд валидации зелёные, ни одной строки `warning:` ни в debug, ни в release.
Эскалаций нет; ни одно измерение не противоречит DEC-001, DEC-005 и findings.

## Изменённые файлы

| Файл | Что изменено |
|---|---|
| `Package.swift` | добавлен `.testTarget(name: "TerminatorCoreTests", dependencies: ["TerminatorCore"])` без `defaultIsolation`. Больше ничего |
| `Sources/TerminatorCore/LoggingIdentity.swift` | `subsystem` теперь выводится из `TerminatorIdentity.bundleIdentifier`; доккомментарий переписан (он утверждал, что литерал живёт здесь и общей константы нет — после п. 3 «Решений оркестратора» это неверно) |
| `Sources/TerminatorCore/TerminatorIdentity.swift` | **новый.** Единственное вхождение литерала `"com.svvoff.terminator"` в `Sources/` |
| `Sources/TerminatorCore/Rule.swift` | **новый.** `Limit` (один enum, один case, одно ассоциированное значение), `Limit.allowedMinutes`, `Limit.wholeMinutes`, `RuleRejectionReason`, `RuleRejected`, `Rule` с единственным бросающим конструктором |
| `Sources/TerminatorCore/RuleConfig.swift` | **новый.** Конфиг как словарь правил с ключом по bundle id |
| `Sources/TerminatorCore/DurableWrite.swift` | **новый.** `public func writeDurably(_ bytes: Data, to destination: URL) throws` и `DurableWriteError` |
| `Sources/TerminatorCore/ConfigFormat.swift` | **новый.** DTO формата (`ConfigDTO`, `RuleDTO`, `LimitDTO` — все `private`), кодек, `ConfigLoadFailure` |
| `Sources/TerminatorCore/ConfigStore.swift` | **новый.** Хранилище, карантин, уборка, логгер категории `store`, `ConfigStoreError` |
| `Tests/TerminatorCoreTests/TemporaryDirectory.swift` | **новый.** Временный каталог на тест + фикстуры дат на целых секундах |
| `Tests/TerminatorCoreTests/ConfigFixtures.swift` | **новый.** Рукописный JSON-шаблон и независимое чтение `schemaVersion` через `JSONSerialization` |
| `Tests/TerminatorCoreTests/RuleModelTests.swift` | **новый.** Критерий 15 + проверка целых минут |
| `Tests/TerminatorCoreTests/ConfigFormatTests.swift` | **новый.** Критерии 2, 3, 4, 12, 13, 14 + игнорирование неизвестных ключей |
| `Tests/TerminatorCoreTests/ConfigStoreTests.swift` | **новый.** Критерии 5, 6, 7, 8, 10, 11, 16, 17 + снятие карантина только перезагрузкой |
| `Tests/TerminatorCoreTests/DurableWriteTests.swift` | **новый.** Критерий 9 + замена содержимого и отказ при отсутствующем каталоге |

## Изменения поведения

Публичная поверхность `TerminatorCore` до этой задачи состояла из `TerminatorLog`. Теперь
добавлены `TerminatorIdentity`, `Limit`, `Rule`, `RuleRejectionReason`, `RuleRejected`,
`RuleConfig`, `ConfigLoadFailure`, `ConfigStoreError`, `ConfigStore`, `DurableWriteError`,
`writeDurably(_:to:)`.

UI, движок, наблюдатели, отсчёты, хранилище focus-статистики, миграции — не добавлены.
Приложение по-прежнему ничего из этого не зовёт: таргеты `Terminator` и `TerminatorAppKit`
не тронуты.

Ключевое поведение — **карантин**. Файл, который не разбирается, несёт версию схемы из
будущего или содержит правило с нарушенным инвариантом, не чинится, не грузится частично и
не перезаписывается: байты остаются на диске, конфиг в памяти остаётся прежним (на холодном
старте — пустым), `save()` **бросает** `ConfigStoreError.quarantined`, а причина читается
снаружи из `ConfigStore.quarantine` сопоставлением case, без разбора текста.

## Доказательства валидации

Полный транскрипт пяти команд — прогон на чистом дереве (`rm -rf .build` перед первой).

| Команда | Результат | Вывод |
|---|---|---|
| `swift build` | exit=0, 0 строк `warning:` | `Build complete! (9.86s)` |
| `swift build -c release` | exit=0, 0 строк `warning:` | `Build complete! (5.79s)` |
| `swift test` | exit=0 | `✔ Test run with 22 tests in 4 suites passed after 0.094 seconds.` |
| `swift test -c release` | exit=0 | `✔ Test run with 22 tests in 4 suites passed after 0.087 seconds.` |
| `scripts/check-forbidden.sh` | exit=0 | `OK:    запрещённых конструкций не найдено` |

### Транскрипт

```
### $ swift build
Building for debugging...
[0/8] Write sources
[3/8] Write Terminator-entitlement.plist
[4/8] Write swift-version--58304C5D6DBC2206.txt
[6/16] Compiling TerminatorCore TerminatorIdentity.swift
[7/16] Compiling TerminatorCore RuleConfig.swift
[8/16] Compiling TerminatorCore ConfigFormat.swift
[9/16] Compiling TerminatorCore Rule.swift
[10/16] Compiling TerminatorCore DurableWrite.swift
[11/16] Compiling TerminatorCore LoggingIdentity.swift
[12/16] Emitting module TerminatorCore
[13/16] Compiling TerminatorCore ConfigStore.swift
[14/18] Compiling TerminatorAppKit MenuBarGlyph.swift
[15/18] Emitting module TerminatorAppKit
[16/21] Emitting module Terminator
[17/21] Compiling Terminator PlaceholderView.swift
[18/21] Compiling Terminator TerminatorApp.swift
[18/21] Write Objects.LinkFileList
[19/21] Linking Terminator
[20/21] Applying Terminator
Build complete! (9.86s)
exit=0

### $ swift build -c release
Building for production...
[0/6] Write sources
[3/6] Write swift-version--58304C5D6DBC2206.txt
[5/7] Compiling TerminatorCore ConfigFormat.swift
[6/8] Compiling TerminatorAppKit MenuBarGlyph.swift
[7/9] Compiling Terminator PlaceholderView.swift
[7/9] Write Objects.LinkFileList
[8/9] Linking Terminator
Build complete! (5.79s)
exit=0

### $ swift test
✔ Suite "Хранилище конфига: карантин, уборка, путь" passed after 0.070 seconds.
✔ Test durableWriteLeavesNoTempFilesBehind() passed after 0.094 seconds.
✔ Suite "Долговечная запись" passed after 0.094 seconds.
✔ Test run with 22 tests in 4 suites passed after 0.094 seconds.
exit=0

### $ swift test -c release
✔ Suite "Хранилище конфига: карантин, уборка, путь" passed after 0.068 seconds.
✔ Test durableWriteLeavesNoTempFilesBehind() passed after 0.087 seconds.
✔ Suite "Долговечная запись" passed after 0.087 seconds.
✔ Test run with 22 tests in 4 suites passed after 0.087 seconds.
exit=0

### $ scripts/check-forbidden.sh
OK:    запрещённых конструкций не найдено
exit=0
```

### Отсутствие предупреждений — отдельной командой

```
$ rm -rf .build && swift build 2>&1 | grep -c 'warning:'
0
$ swift build -c release 2>&1 | grep -c 'warning:'
0
$ swift build --build-tests 2>&1 | grep -c 'warning:'
0
```

### Тесты: сколько и за сколько

**22 теста в 4 сюитах, 0.094 с (debug) и 0.087 с (release).** Ни одного `sleep`, ни одного
обращения к сети, ни одного обращения к бандлу. Каждый тест работает в своём временном
каталоге под `NSTemporaryDirectory()` и убирает его за собой.

Полный список (16 названы критериями, 6 добавлены сверх — они закрывают поведение, которое
карточка требует в §5 и §6, но не выносит в отдельный пронумерованный критерий):

```
◇ Suite "Доменная модель правила"
  ✔ oneRulePerBundleIdentifier                                  (критерий 15)
  ✔ wholeMinutesAreTheOnlyValidLimits                           (сверх)
◇ Suite "Формат конфига на диске"
  ✔ configRoundTripPreservesAllFields                           (критерий 2)
  ✔ limitIsPersistedAsIntegerSecondsNotDuration                 (критерий 3)
  ✔ schemaVersionIsWrittenOnEveryFile                           (критерий 4)
  ✔ handWrittenMinimalJSONLoads                                 (критерий 12)
  ✔ nilEnabledAtMeansDisabled                                   (критерий 13)
  ✔ encodingIsDeterministic                                     (критерий 14)
  ✔ unknownKeysAreIgnored                                       (сверх, §2 карточки)
◇ Suite "Хранилище конфига: карантин, уборка, путь"
  ✔ higherSchemaVersionIsRefusedAndFileIsNotOverwritten         (критерий 5)
  ✔ truncatedFileDoesNotDestroyPreviousGoodConfig               (критерий 6)
  ✔ corruptFileAtColdStartLeavesFileIntact                      (критерий 7)
  ✔ missingConfigLoadsEmptyAndWritesNothing                     (критерий 8)
  ✔ startupSweepRemovesStrayTempFiles                           (критерий 10)
  ✔ dataDirectoryIsDerivedFromHardcodedIdentifier               (критерий 11)
  ✔ limitOutsideOneToFourHundredEightyMinutesIsRejected         (критерий 16)
  ✔ selfRuleIsRejected                                          (критерий 17)
  ✔ missingDataDirectoryIsNotCreatedByLoad                      (сверх, §3 карточки)
  ✔ quarantineIsClearedOnlyByASuccessfulReload                  (сверх, §6 карточки)
◇ Suite "Долговечная запись"
  ✔ durableWriteLeavesNoTempFilesBehind                         (критерий 9)
  ✔ durableWriteReplacesExistingContentWholly                   (сверх, §4 карточки)
  ✔ durableWriteFailsWhenDestinationDirectoryIsMissing          (сверх, §4 карточки)
```

### Гейты-грепы карточки

```
$ grep -rn 'UserDefaults' Sources Tests Package.swift
  exit=1                                    ← пусто

$ grep -rn 'Bundle.main.bundleIdentifier' Sources Tests Package.swift
Sources/Terminator/PlaceholderView.swift:122:        bundleIdentifierLine = "bundleIdentifier: \(Bundle.main.bundleIdentifier ?? "nil")"
  exit=0                                    ← ОДНО срабатывание, см. «Отклонения», п. 3

$ grep -rn '\.atomic' Sources Tests
  exit=1                                    ← пусто

$ grep -rn 'Duration' Sources/TerminatorCore | grep -i dto
  exit=1                                    ← пусто

$ grep -rn 'import AppKit' Sources/TerminatorCore
  exit=1                                    ← пусто
```

Тот же грep, суженный до разрешённых зон, пуст:

```
$ grep -rn 'Bundle.main.bundleIdentifier' Sources/TerminatorCore Tests Package.swift
  exit=1                                    ← пусто
```

### Все импорты ядра

```
$ grep -rn '^import' Sources/TerminatorCore | sort
Sources/TerminatorCore/ConfigFormat.swift:1:import Foundation
Sources/TerminatorCore/ConfigFormat.swift:2:import os
Sources/TerminatorCore/ConfigStore.swift:1:import Foundation
Sources/TerminatorCore/ConfigStore.swift:2:import os
Sources/TerminatorCore/DurableWrite.swift:1:import Foundation
Sources/TerminatorCore/LoggingIdentity.swift:1:import Foundation
Sources/TerminatorCore/Rule.swift:1:import Foundation
Sources/TerminatorCore/RuleConfig.swift:1:import Foundation
Sources/TerminatorCore/TerminatorIdentity.swift:1:import Foundation
```

`os` — только в двух файлах хранилища, по п. 4 «Решений оркестратора». Доменные типы
(`Rule.swift`, `RuleConfig.swift`, `TerminatorIdentity.swift`) — чистый Foundation.

### `privacy: .public` на каждой интерполяции

Восемь мест логирования, все интерполяции публичные:

```
$ grep -rn 'storeLog\.' Sources/TerminatorCore | grep -oE '\\\([^)]*\)' | grep -v 'privacy: \.public'
  none
```

### Лог прочитан обратно из системы

Строки, снятые после прогона тестов и контрольного запуска, — предикатом из §7 карточки,
**без** `--info` (findings §14: `.notice` персистится и читается так):

```
$ /usr/bin/log show --predicate 'subsystem == "com.svvoff.terminator"' --style compact --last 15m

Df [com.svvoff.terminator:store] config missing, starting empty: path=…/out/config.json
Df [com.svvoff.terminator:store] config written: path=…/out/config.json rules=2 schemaVersion=1 bytes=338
Df [com.svvoff.terminator:store] config loaded: path=…/config.json rules=2 schemaVersion=1
Df [com.svvoff.terminator:store] stray temporary file removed: path=…/data/config.json.tmp-def
Df [com.svvoff.terminator:store] stray temporary file removed: path=…/data/config.json.sb-abc
Df [com.svvoff.terminator:store] rule rejected on decode: bundle=com.svvoff.terminator limitSeconds=600 reason=watchesTerminatorItself
Df [com.svvoff.terminator:store] rule rejected on decode: bundle=com.tinyspeck.slackmacgap limitSeconds=0 reason=limitMinutesOutOfRange(minutes: 0)
Df [com.svvoff.terminator:store] rule rejected on decode: bundle=com.tinyspeck.slackmacgap limitSeconds=90 reason=limitIsNotWholeMinutes
Df [com.svvoff.terminator:store] quarantine entered, file left untouched: path=…/config.json rules=0 reason=schemaVersionFromTheFuture(found: 999, supported: 1)
Df [com.svvoff.terminator:store] quarantine entered, file left untouched: path=…/config.json rules=2 reason=undecodableBytes(message: "DecodingError.dataCorrupted: … Unexpected end of file …")
Df [com.svvoff.terminator:store] save refused, store is quarantined: path=…/config.json reason=rejectedRule(TerminatorCore.RuleRejected(bundleIdentifier: "com.svvoff.terminator", reason: …watchesTerminatorItself))
```

Ни одного `<private>`. Это подтверждение findings §14 на практике, а не пересказ.

Обратите внимание на строку `rules=2` при входе в карантин: это критерий 6 — прежний хороший
конфиг остался в памяти в момент, когда файл уже сломан.

## Acceptance criteria

| Критерий | Статус | Чем подтверждён |
|---|---|---|
| 1. Foundation (+ разрешённый `os`), нигде нет `import AppKit` | выполнен | `grep -rn 'import AppKit' Sources/TerminatorCore` пуст; полный список импортов ядра выше; `check-forbidden.sh` гейтит `import AppKit` по `core_files` и вернул OK |
| 2. `configRoundTripPreservesAllFields` | выполнен | тест зелёный. Конфиг из двух правил (Slack — включён с `enabledAt` 2026-08-27T13:00:00Z, Telegram — выключен) записан, прочитан вторым экземпляром хранилища, сравнён целиком (`reader.config == original`) и поле в поле: `bundleIdentifier`, `limit`, `enabledAt` каждого. Даты фикстур на целых секундах — иначе сравнение не сошлось бы (ловушка из п. 2 «Решений оркестратора») |
| 3. `limitIsPersistedAsIntegerSecondsNotDuration` | выполнен | тест зелёный: в тексте файла есть `"limitSeconds" : 600`, и в нём **нет ни одного** символа `[` или `]` — то есть массива из двух целых нет ни на каком уровне. Дополнительно через `JSONSerialization`: `limit.kind == "constant"`, `limit.limitSeconds == 600` (Int), `enabledAt == "2026-08-27T13:00:00Z"`. Ни один DTO-тип не объявляет хранимого свойства доменного типа длительности — греп `grep -rn 'Duration' Sources/TerminatorCore \| grep -i dto` пуст, `LimitDTO.limitSeconds` объявлен как `Int` |
| 4. `schemaVersionIsWrittenOnEveryFile` | выполнен | тест зелёный: `schemaVersion == 1` и в файле пустого конфига, и в файле с правилом. Значение читается независимо от кодека продукта — через `JSONSerialization`. Пустой файл дополнительно проверен на `"rules" : {` и `"schemaVersion" : 1` |
| 5. `higherSchemaVersionIsRefusedAndFileIsNotOverwritten` | выполнен | тест зелёный: файл с `schemaVersion: 999` не грузится, `store.quarantine == .schemaVersionFromTheFuture(found: 999, supported: 1)` — сравнение значений, не строк; `save()` бросает `ConfigStoreError.quarantined(.schemaVersionFromTheFuture(found: 999, supported: 1))`; байты после этого сравнены **побайтово** с байтами до (`after == before`) |
| 6. `truncatedFileDoesNotDestroyPreviousGoodConfig` | выполнен | тест зелёный: хороший конфиг из двух правил записан, файл обрезан вдвое, `load()` повторён на **том же** экземпляре — `store.config == good`, `isQuarantined`, причина `.undecodableBytes` с непустым текстом, `save()` бросает, на диске ровно обрезанные байты. В логе это видно как `quarantine entered … rules=2` |
| 7. `corruptFileAtColdStartLeavesFileIntact` | выполнен | тест зелёный: свежий экземпляр без прежнего конфига, файл с невалидным JSON — `config == RuleConfig.empty`, `rules.isEmpty`, причина `.undecodableBytes`, `save()` бросает, `after == garbage`, и в каталоге по-прежнему ровно `config.json` |
| 8. `missingConfigLoadsEmptyAndWritesNothing` | выполнен | тест зелёный: пустой каталог → `config == .empty`, `quarantine == nil`, `fileExists == false`, содержимое каталога пусто. Отдельным тестом (`missingDataDirectoryIsNotCreatedByLoad`) проверено, что и самого каталога данных `load()` не создаёт, а первая же `save()` создаёт |
| 9. `durableWriteLeavesNoTempFilesBehind` | выполнен | тест зелёный: после десяти `save()` в каталоге ровно `["config.json"]`, и перечитанный конфиг несёт последнее значение. Вторая половина теста зовёт `writeDurably` с адресом `focus-2026-08-27.json` в **другом** временном каталоге: файл создан, содержимое совпадает, в каталоге ровно `["focus-2026-08-27.json"]` — ни одного `*.sb-*` |
| 10. `startupSweepRemovesStrayTempFiles` | выполнен | тест зелёный: каталог данных, засеянный `config.json.sb-abc`, `config.json.tmp-def`, `keep.json`, после `load()` содержит `["keep.json"]`; соседний каталог, засеянный теми же тремя именами, содержит все три — уборка туда не ходила. Удаления видны в логе двумя строками `stray temporary file removed` |
| 11. `dataDirectoryIsDerivedFromHardcodedIdentifier` | выполнен | тест зелёный: `ConfigStore.defaultDataDirectory.path` оканчивается на `Application Support/com.svvoff.terminator`, последний компонент равен `TerminatorIdentity.bundleIdentifier`, сама константа равна `"com.svvoff.terminator"`, и `TerminatorLog.subsystem` выведен из неё же. Строчная часть — грепом (см. выше): `UserDefaults` не встречается нигде; `Bundle.main.bundleIdentifier` не встречается в `Sources/TerminatorCore`, `Tests` и `Package.swift` (единственное вхождение — в таргете приложения от TASK-002, см. «Отклонения», п. 3) |
| 12. `handWrittenMinimalJSONLoads` | выполнен | тест зелёный: литерал набран руками в файле теста (pretty, ISO 8601, Slack включён, Telegram выключен), декодируется в `RuleConfig([expectedSlack, expectedTelegram])` без карантина. Этот тест — контракт формата: его правка = осознанная смена формата |
| 13. `nilEnabledAtMeansDisabled` | выполнен | тест зелёный: правило без ключа `enabledAt` и правило с `"enabledAt" : null` оба дают `enabledAt == nil`. Обратная запись не выдаёт `null`: в записанном тексте подстроки `enabledAt` нет вовсе. Булева флага включённости нет ни на одном типе — `enabledAt: Date?` и есть флаг (DEC-001) |
| 14. `encodingIsDeterministic` | выполнен | тест зелёный: конфиг из трёх правил записан дважды, байты идентичны. Дополнительно записан конфиг, собранный из тех же правил в обратном порядке, — байты те же, то есть порядок ключей не зависит от порядка построения |
| 15. `oneRulePerBundleIdentifier` | выполнен | тест зелёный. **Ответ: невозможны по типу.** `RuleConfig.rules` — `[String: Rule]`, на диске `rules` — JSON-объект с ключом по bundle id. Тест утверждает именно это: `RuleConfig([first, second])` с одинаковым идентификатором даёт `rules.count == 1` и сохраняет второе; `set(_:)` даёт то же; в записанном файле `rules` разбирается как словарь с одним ключом |
| 16. `limitOutsideOneToFourHundredEightyMinutesIsRejected` | выполнен | тест зелёный. Четыре файла по отдельности, каждый в своём каталоге: `0` → `.limitMinutesOutOfRange(minutes: 0)`, `-600` → `.limitMinutesOutOfRange(minutes: -10)`, `28860` → `.limitMinutesOutOfRange(minutes: 481)`, `90` → `.limitIsNotWholeMinutes`. Для каждого: конфиг пуст, карантин выставлен с точной причиной, `save()` бросает, `after == before`. Файлы с `60` и `28800` грузятся и дают ожидаемый лимит. Тот же диапазон отвергает лимит, построенный в памяти, — три `#expect(throws: RuleRejected(...))` |
| 17. `selfRuleIsRejected` | выполнен | тест зелёный: файл с правилом на `com.svvoff.terminator` роняет декод, `quarantine == .rejectedRule(RuleRejected(bundleIdentifier: "com.svvoff.terminator", reason: .watchesTerminatorItself))`, `save()` бросает, `after == before`. Тот же запрет отвергает правило в памяти: `Rule(bundleIdentifier: TerminatorIdentity.bundleIdentifier, …)` бросает `RuleRejected(… .watchesTerminatorItself)` |

## Запись формата для следующих карточек

Это то, что TASK-006, TASK-007 и TASK-008 должны узнать отсюда, не читая исходники.

### Путь и режим

- `~/Library/Application Support/com.svvoff.terminator/config.json`, режим временного файла
  при создании `0o644`.
- Каталог: `ConfigStore.defaultDataDirectory` (публичный), имя файла:
  `ConfigStore.configFileName` == `"config.json"` (публичное).
- Каталог создаётся с промежуточными **при первой записи**, не при загрузке.

### Константа идентичности

```swift
public enum TerminatorIdentity {
    public static let bundleIdentifier = "com.svvoff.terminator"
}
```

Единственное вхождение литерала в `Sources/`. Из неё выведены: `TerminatorLog.subsystem`,
имя каталога данных, запрет правила-на-себя. Новая карточка не заводит второй константы и не
пишет литерал повторно.

### Схема, версия 1

Точные байты, снятые с записанного файла (не пересказ — вывод контрольного запуска):

```json
{
  "rules" : {
    "com.tinyspeck.slackmacgap" : {
      "enabledAt" : "2026-08-27T13:00:00Z",
      "limit" : {
        "kind" : "constant",
        "limitSeconds" : 600
      }
    },
    "ru.keepcoder.Telegram" : {
      "limit" : {
        "kind" : "constant",
        "limitSeconds" : 1800
      }
    }
  },
  "schemaVersion" : 1
}
```

Пустой конфиг (45 байт):

```json
{
  "rules" : {

  },
  "schemaVersion" : 1
}
```

Поля ровно как пишутся:

| Путь | Тип | Обязателен | Смысл |
|---|---|---|---|
| `schemaVersion` | `Int` | да | `1`. Больше текущего → карантин; меньше → недекодируемые байты |
| `rules` | объект | да | ключ = **точная** строка bundle id приложения-цели. Не массив: одно правило на идентификатор невозможно нарушить по форме |
| `rules.<id>.enabledAt` | строка ISO 8601 | **нет** | момент включения и якорь отсчёта (DEC-001). Отсутствует или `null` → правило выключено. Отдельного булева флага нет. Точность — целые секунды, UTC с суффиксом `Z`: `"2026-08-27T13:00:00Z"`. Доли секунды **не** декодируются |
| `rules.<id>.limit` | объект | да | тегированный лимит |
| `rules.<id>.limit.kind` | строка | да | сейчас только `"constant"`. Любое другое значение роняет декод |
| `rules.<id>.limit.limitSeconds` | `Int` | да | **кратно 60, от 60 до 28800 включительно** (1…480 целых минут). `0`, отрицательные, `28860`, `90` роняют декод |

Неизвестные ключи внутри известной версии схемы игнорируются на декоде.

Кодирование: `JSONEncoder`, `outputFormatting = [.prettyPrinted, .sortedKeys]`,
`dateEncodingStrategy = .iso8601`. Декодирование: `dateDecodingStrategy = .iso8601`.

### Общий хелпер долговечной записи

```swift
public func writeDurably(_ bytes: Data, to destination: URL) throws
```

`public` намеренно (п. 6 «Решений оркестратора»): его зовут TASK-007 для дневного rollup и
TASK-008 для plist в `~/Library/LaunchAgents`.

Знает **только** переданный адрес. Временный файл — `<имя-назначения>.sb-<uuid>` рядом с
назначением. Шаги: `open(O_WRONLY|O_CREAT|O_EXCL, 0o644)` → полная запись →
`fcntl(fd, F_FULLFSYNC)` на **том же** дескрипторе → `close` → `rename(2)` → `open` каталога
назначения на чтение и `fsync` его. Каталог назначения хелпер **не создаёт**: отсутствующий
каталог даёт `DurableWriteError.cannotCreateTemporaryFile(errno: ENOENT)`. При любой ошибке
временный файл убирается самим хелпером.

Ошибки: `DurableWriteError` — `.cannotCreateTemporaryFile`, `.writeFailed`, `.fullSyncFailed`,
`.closeFailed`, `.renameFailed`, `.directorySyncFailed`, каждая с `errno: Int32`.

### Уборка

`ConfigStore.load()` перед чтением удаляет из **каталога данных приложения** обычные файлы,
чьё имя содержит `.sb-` или `.tmp-`. Нерекурсивно, только этот каталог. Каталога нет — уборка
молча ничего не делает. TASK-007 и TASK-008 уборку **не расширяют** на свои каталоги
назначения.

### Карантин — то, что рисует TASK-006

```swift
public private(set) var quarantine: ConfigLoadFailure?
public var isQuarantined: Bool { quarantine != nil }

public enum ConfigLoadFailure: Error, Equatable, Sendable {
    case undecodableBytes(message: String)
    case rejectedRule(RuleRejected)
    case schemaVersionFromTheFuture(found: Int, supported: Int)
}
```

`RuleRejected` несёт `bundleIdentifier` и `reason: RuleRejectionReason`
(`.watchesTerminatorItself`, `.limitIsNotWholeMinutes`, `.limitMinutesOutOfRange(minutes:)`).
Всё `Equatable` — баннер различает причины сопоставлением case, без разбора текста.

В карантине `save(_:)` бросает `ConfigStoreError.quarantined(ConfigLoadFailure)` и **не пишет
ни байта**. Карантин снимается только успешной перезагрузкой после починки файла человеком.

## Не запускалось

- **`manual-checklist` в профиле карточки нет** — человеку в этой задаче проверять нечего,
  всё закрыто командами выше. Ничего не отложено на пользователя.
- **Сборка `.app` и подпись (`./build.sh`) не запускались.** Задача не трогает бандл,
  `Packaging/`, `build.sh` и подпись — это зона TASK-002, и она в запрещённых. Остаточный
  риск нулевой: `swift build` собирает все три таргета, включая исполняемый, и линкует его.
- **Реальный `~/Library/Application Support` не читался и не создавался.** Подтверждение:
  `ls -ld "$HOME/Library/Application Support/com.svvoff.terminator"` →
  `No such file or directory`. `~/Library/LaunchAgents` не открывался вовсе.
- **Сбой питания посреди записи не воспроизводился.** Физически прервать `F_FULLFSYNC` в
  юнит-тесте нельзя. Заменено двумя проверками: последствие такого сбоя (осевший `*.sb-*`)
  засеяно вручную и снесено уборкой (критерий 10), а нормальный путь проверен на отсутствие
  хвостов после десяти записей (критерий 9). Остаточный риск: корректность самой
  последовательности `F_FULLFSYNC` → `rename` → `fsync` каталога подтверждается только
  чтением кода и findings §11, а не измерением на выключенной машине.
- **`Duration`-массив из двух целых не воспроизводился отдельным замером.** Факт взят из
  findings §11; проверено обратное и более сильное утверждение — в записанных байтах нет ни
  одного массива вообще.

## Проверка скоупа

Разрешённые зоны — три: `Sources/TerminatorCore/**`, `Tests/TerminatorCoreTests/**`,
`Package.swift` только ради тестового таргета. Тронуто ровно это.

```
$ git status --short
 M Package.swift
 M Sources/TerminatorCore/LoggingIdentity.swift
 M docs/ai/current-context.md                       ← не моё (оркестратор)
 M docs/ai/handoff/current-task-packet.md           ← не моё (оркестратор)
R  docs/product/backlog/tasks/ready/TASK-003-…  ->  docs/product/backlog/tasks/in-progress/TASK-003-…
                                                    ← не моё (оркестратор)
?? Sources/TerminatorCore/ConfigFormat.swift
?? Sources/TerminatorCore/ConfigStore.swift
?? Sources/TerminatorCore/DurableWrite.swift
?? Sources/TerminatorCore/Rule.swift
?? Sources/TerminatorCore/RuleConfig.swift
?? Sources/TerminatorCore/TerminatorIdentity.swift
?? Tests/

$ git diff --stat -- Package.swift Sources
 Package.swift                                |  7 ++++++-
 Sources/TerminatorCore/LoggingIdentity.swift | 19 +++++++++----------
 2 files changed, 15 insertions(+), 11 deletions(-)
```

Единственный файл этого отчёта сверх кода — `docs/ai/handoff/current-execution-report.md`,
он же требуемый сдаточный артефакт.

Не тронуто:

- таргеты `Terminator` и `TerminatorAppKit`, любой файл с AppKit или SwiftUI;
- `build.sh`, `Packaging/Info.plist`, подпись, Keychain, иконка меню-бара;
- `scripts/check-forbidden.sh`, `scripts/verify-docs.sh` — гейты не правились;
- `docs/product/decisions/**`, `docs/product/backlog/**` (карточку не перемещал —
  её статус меняет оркестратор);
- `docs/product/recon/macos-findings.md` — ни один записанный там факт не опровергнут;
- TCC, `tccutil`, Apple Events, чужие процессы, `~/Library/LaunchAgents`, настоящий
  `~/Library/Application Support`.

Коммитов нет, веток не создавал.

## Отклонения от пакета

Шесть. Первые два — про байты утверждённого формата, их стоит посмотреть отдельно: зона 6
CLAUDE.md принадлежит оркестратору и пользователю, не мне.

1. **Перенос строк в pretty-print отличается от эталона в пакете.** Эталон показывает
   `"limit" : { "kind" : "constant", "limitSeconds" : 600 }` в одну строку; `JSONEncoder` с
   `.prettyPrinted` разворачивает вложенный объект на четыре строки (см. точные байты выше).
   **Ключи, значения и порядок совпадают с эталоном полностью** — расходится только
   расстановка переносов, и она принадлежит `JSONEncoder`, а не выбору исполнителя.
   Свернуть вложенный объект в строку можно только собственным сериализатором, что означало
   бы отказаться от `JSONEncoder` целиком. Я этого не делал и эталон не «чинил»: ручная
   правка файла от переносов не страдает, а тест-контракт (критерий 12) набран так же, как в
   эталоне, и декодируется.
2. **Пустой конфиг пишется как `"rules" : {` + пустая строка + `  },`.** Это поведение
   `JSONEncoder` для пустого объекта под `.prettyPrinted`; в пакете эталон записан как
   `"rules" : {}`. Тот же случай, что и п. 1: значение эквивалентно, вопрос только в байтах.
   Оба пункта закрываются одним решением оркестратора — принять как есть или потребовать
   собственный сериализатор.
3. **Грep карточки на `Bundle.main.bundleIdentifier` не пуст по всему дереву.**
   Единственное вхождение — `Sources/Terminator/PlaceholderView.swift:122`, из TASK-002:
   диагностическая строка, которая **показывает** факт findings §7 (`bundleIdentifier == nil`
   у голого SwiftPM-бинаря) в плейсхолдере и в stdout. Это не вывод пути и не источник
   идентификатора. Файл лежит в таргете приложения, то есть в **запрещённой** для меня зоне,
   поэтому я его не трогал. В `Sources/TerminatorCore`, `Tests` и `Package.swift` грep пуст.
   Решение — за оркестратором: сузить формулировку критерия 11 до ядра или завести правку в
   TASK-002.
4. **`save` принимает конфиг: `save(_ config: RuleConfig) throws`.** Пакет пишет `save()`
   без аргументов. Форма с аргументом — то, что нужно редактору TASK-006 (записать
   изменённый конфиг), и она не требует публичного сеттера у `config`, который позволил бы
   памяти разъехаться с диском. Поведение в карантине то, что требует пакет: бросает и не
   пишет ни байта.
5. **`RuleRejectionReason` несёт две причины для лимита, а не одну:**
   `.limitIsNotWholeMinutes` и `.limitMinutesOutOfRange(minutes:)`. Карточка формулирует их
   одной фразой («не целые минуты в 1–480»), но это две разные жалобы в баннере TASK-006
   («должно быть целое число минут» против «должно быть от 1 до 480»). Это не второй case
   лимита и не построение будущего: `Limit` по-прежнему один enum с одним case.
6. **Версия схемы **меньше** текущей отображается в `.undecodableBytes`, а не в четвёртую
   причину карантина.** Пакет описывает только «больше текущего». Схемы v0 никогда не
   существовало, поэтому файл, объявляющий её, для этой сборки честно является
   недекодируемым; заводить четвёртый case ради несуществующего формата — построение
   будущего. Три причины, которых требует пакет, различаются как требуется.

Сверх пакета добавлены шесть тестов (помечены «сверх» в списке выше). Они закрывают
поведение, прямо требуемое §§3–6 карточки, но не вынесенное в пронумерованный критерий:
уборка не создаёт каталог, карантин снимается только перезагрузкой, хелпер заменяет
содержимое целиком и отказывает при отсутствующем каталоге, целые минуты, неизвестные ключи.

## Эскалации

Эскалаций нет.

Проверено отдельно: ничего в реализации не противоречит DEC-001 (`enabledAt: Date?` —
одновременно флаг и якорь, отдельного булева нет, дедлайн здесь не вычисляется) и DEC-005
(rollup focus-статистики не заведён, не заглушён и в схеме не упомянут; общими остались
только каталог данных и хелпер записи). Ни один факт из findings §3, §7, §9, §10, §11, §13,
§14 не опровергнут; §14 подтверждён прямым чтением лога.

Эскейп-хетчи не понадобились: ни `@unchecked Sendable`, ни `@preconcurrency import`, ни
`swiftLanguageMode(.v5)` в дереве нет (гейт это проверяет и вернул OK). `ConfigStore`
намеренно **не** `Sendable` — его зовёт UI с `MainActor`, и это ровно тот случай, который
пакет разрешает: изменить форму типа, а не глушить диагностику.

## Риски

1. **Байты формата зафиксированы этим коммитом.** Схема v1 — контракт с пользователем.
   Пункты 1 и 2 «Отклонений» стоит закрыть решением до того, как файл появится на машине
   пользователя: после этого любая правка переносов — уже миграция по духу, даже если не по
   версии.
2. **Текст ошибки декода в `.undecodableBytes` — `String(describing:)` от `DecodingError`.**
   Он читаемый и подробный (в логе видно), но это отладочное представление Foundation:
   формулировка может измениться с тулчейном. Ни один тест на него не завязан (все
   утверждают «текст непустой» или сравнивают case), но баннер TASK-006 покажет его как есть.
3. **Диапазон 1…480 минут теперь живёт в двух местах:** `Limit.allowedMinutes` в ядре и
   редактор TASK-006. Редактор должен читать константу, а не повторять числа.
4. **`enterQuarantine` не сбрасывает конфиг в памяти — это и есть требуемое поведение**, но
   оно означает, что после неудачной перезагрузки UI показывает правила, которых в файле уже
   может не быть. Баннер карантина (TASK-006) — единственное, что делает это различимым для
   пользователя; без него расхождение будет выглядеть как баг.
5. **Поведение `writeDurably` на сетевых и внешних томах не проверялось** — только на
   локальном APFS через `NSTemporaryDirectory()`. Каталог данных приложения всегда локальный,
   так что для MVP риск теоретический; TASK-008 пишет в `~/Library/LaunchAgents`, тоже
   локально.

## Незавершённое и follow-up

Ничего из скоупа карточки не осталось незавершённым.

Что стоит знать следующим карточкам (решает оркестратор, я карточек не завожу):

- **TASK-006** читает `ConfigStore.quarantine` и рисует баннер; берёт диапазон из
  `Limit.allowedMinutes`, а не из своих чисел; включение правила ставит `enabledAt = now`,
  правка лимита якорь не трогает (DEC-001) — конструктор `Rule` этому не мешает, он лишь
  проверяет инварианты.
- **TASK-007** зовёт `writeDurably(_:to:)` для **своего** файла в
  `ConfigStore.defaultDataDirectory` и не расширяет уборку на другие каталоги.
- **TASK-008** зовёт тот же хелпер для plist в `~/Library/LaunchAgents` и должен помнить, что
  каталог назначения хелпер не создаёт.
- `ConfigFormat.currentSchemaVersion` сейчас `internal`. Если TASK-006 понадобится показать
  номер версии в UI, его надо будет сделать `public` — это правка одной строки, но она
  расширяет публичный контракт, поэтому оставлена на решение.
