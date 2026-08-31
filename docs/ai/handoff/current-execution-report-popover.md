# Отчёт об исполнении — TASK-006, раунд 6 (поток `-popover`)

## Задача

TASK-006, амендмент 7: строки списка перестают двигаться. Порядок строк становится
**стабильным**: `bundleIdentifier` по возрастанию и больше ничем. Убираются `sortRank`,
бакетизация (запущенные / без экземпляра / выключенные) и сортировка по остатку. Четыре
теста вычёркиваются, три добавляются; число тестов идёт с 83 на 82.

## Кратко

Компаратор `PopoverViewModel.precedes` и свойство `PopoverRow.sortRank` удалены целиком.
Сортировка строк — одна строка кода: `unsorted.sorted { $0.bundleIdentifier < $1.bundleIdentifier }`.
Второго ключа не осталось; ни один бакет не уцелел.

Изменено ровно два файла, оба разрешены пакетом. Экземпляры внутри строки по-прежнему идут по
`SessionKey` — эта сортировка не тронута. `Sources/Terminator/`, `Sources/TerminatorAppKit/`,
формат `config.json` не тронуты.

82 теста в 8 сьютах, ноль `warning:` в debug и release, `check-forbidden.sh` EXIT=0,
`./build.sh` EXIT=0.

## Изменённые файлы

| Файл | Что изменено |
|---|---|
| `Sources/TerminatorCore/PopoverViewModel.swift` | удалён `private static func precedes`; удалено `PopoverRow.sortRank`; сортировка строк заменена на `bundleIdentifier` по возрастанию; комментарий о порядке переписан; доккомментарий `soonestRemaining` перестал называть его ключом сортировки |
| `Tests/TerminatorCoreTests/PopoverViewModelTests.swift` | минус четыре теста порядка, плюс три теста стабильности; добавлены две фикстуры bundle id (`textEdit`, `printCenter`) |

## Дифф дословно

```diff
diff --git a/Sources/TerminatorCore/PopoverViewModel.swift b/Sources/TerminatorCore/PopoverViewModel.swift
@@ -48,22 +48,27 @@ public struct PopoverViewModel: Equatable, Sendable {
             )
         }
 
-        self.rows = unsorted.sorted(by: PopoverViewModel.precedes)
+        // Порядок строк — по `bundleIdentifier` по возрастанию и больше ничем: см. ниже.
+        self.rows = unsorted.sorted { $0.bundleIdentifier < $1.bundleIdentifier }
         self.banner = quarantine.map(PopoverBanner.init(_:))
     }
 
     // MARK: - Порядок строк
 
-    /// Порядок: сначала правила с запущенными экземплярами по возрастанию **минимального**
-    /// остатка, затем правила без запущенных экземпляров, затем выключенные. Ничьи — по
-    /// `bundleIdentifier` по возрастанию, чтобы порядок был детерминирован.
-    private static func precedes(_ lhs: PopoverRow, _ rhs: PopoverRow) -> Bool {
-        if lhs.sortRank != rhs.sortRank { return lhs.sortRank < rhs.sortRank }
-        if let left = lhs.soonestRemaining, let right = rhs.soonestRemaining, left != right {
-            return left < right
-        }
-        return lhs.bundleIdentifier < rhs.bundleIdentifier
-    }
+    // Порядок строк — **стабильный**: `bundleIdentifier` по возрастанию, второго ключа нет.
+    //
+    // Бакеты (запущенные / без экземпляра / выключенные) и сортировка по остатку убраны
+    // намеренно: все их входы меняются при открытом поповере — отсчёт тикает каждую секунду,
+    // приложение запускается и выходит, тумблер щёлкает, — и строка уезжала из-под курсора
+    // ровно тогда, когда правило собирались выключить. Уцелевший бакет — это бакет, между
+    // которыми строка может переехать, поэтому вторичного признака не остаётся вовсе.
+    //
+    // Ключ — bundle id, а не имя приложения: имя резолвится из окружения, и порядок стал бы
+    // функцией того, что установлено на машине и на каком языке система. Bundle id уже
+    // является ключом сопоставления (findings §10) и не меняется никогда. Сравнение —
+    // обычное строковое, поэтому `com.apple.TextEdit` идёт перед `com.apple.printcenter`.
+    //
+    // Ключи `config.rules` уникальны, так что порядок полный и детерминированный.
 
     // MARK: - Остаток
 
@@ -161,16 +166,11 @@ public struct PopoverRow: Equatable, Sendable {
         self.instances = instances
     }
 
-    /// Ключ сортировки: минимальный остаток среди экземпляров правила.
+    /// Минимальный остаток среди экземпляров правила. На порядок строк **не влияет**:
+    /// порядок — это bundle id и ничто другое.
     public var soonestRemaining: TimeInterval? {
         instances.map(\.remaining).min()
     }
-
-    /// Группа порядка: 0 — идут отсчёты, 1 — включено, но не запущено, 2 — выключено.
-    var sortRank: Int {
-        if !isEnabled { return 2 }
-        return instances.isEmpty ? 1 : 0
-    }
 }
```

Тестовый файл — полный дифф в `git diff Tests/TerminatorCoreTests/PopoverViewModelTests.swift`;
ниже он разобран поимённо. Кроме тестов порядка и двух новых фикстур bundle id в файле не
изменено ничего: тесты формата остатка, пустого состояния, двух экземпляров, редактора лимита,
баннера карантина и красных глаз остались дословно теми же.

## Изменения поведения

- Строки поповера идут по `bundleIdentifier` по возрастанию. Порядок не зависит ни от остатка
  времени, ни от того, запущено ли приложение, ни от того, включено ли правило.
- `PopoverRow.sortRank` больше не существует (был `internal`, наружу модуля не выходил —
  ломать в `Sources/Terminator/` нечего, что подтверждено грепом: единственным его
  потребителем был `precedes`).
- `PopoverRow.soonestRemaining` **сохранён**: он публичный и его проверяет уцелевший тест
  `ruleWithTwoRunningInstancesYieldsTwoRemainingTimes` (`row.soonestRemaining == 180`).
  Удаление потребовало бы правки теста, не названного пакетом. Изменён только его
  доккомментарий, который называл его ключом сортировки и стал бы ложью.
- Видимое следствие, названное в амендменте: `com.apple.TextEdit` стоит перед
  `com.apple.printcenter` — заглавная `T` предшествует строчной `p` при строковом сравнении.
  Это зафиксировано тестом, а не оставлено на удачу.

## Тесты: четыре вычеркнуты, три добавлены

Вычеркнуты (все четыре запирали убираемое поведение):

| Тест | Что запирал |
|---|---|
| `rowsSortAscendingByRemainingTime` | сортировку по остатку |
| `rulesWithNoRunningInstanceSortAfterRunningOnes` | бакет «без экземпляра» |
| `disabledRulesSortLast` | бакет «выключено» |
| `equalRemainingTimesBreakTieByBundleIdentifier` | поглощён: при одном ключе ломать нечего |

Добавлены:

| Тест | Что утверждает |
|---|---|
| `rowsSortByBundleIdentifierAscending` | порядок — bundle id по возрастанию, и ничто другое на него не влияет |
| `rowOrderDoesNotChangeAsRemainingTimeChanges` | те же правила при двух разных `now` дают один и тот же порядок |
| `rowOrderDoesNotChangeWhenARuleIsDisabledOrItsAppExits` | выключение правила и выход его приложения — каждое по отдельности — порядок не меняют |

## Чем новые тесты ловят нестабильность, а не только ключ

Требование пакета: тест на один ключ прошёл бы и на реализации, которая всё ещё переупорядочивает
по другому входу. Проверено **мутационно** — реализация временно ломалась, тесты запускались,
затем файл восстанавливался из копии (итоговое дерево содержит принятую реализацию; см. «Проверка
скоупа»).

**Мутация 1 — прежняя реализация целиком** (бакет `sortRank`, затем остаток, затем bundle id).
Падают все три новых теста, 9 issues:

```
✘ rowsSortByBundleIdentifierAscending — 2 issues
  ["ru.keepcoder.Telegram", "com.apple.TextEdit", "com.tinyspeck.slackmacgap",
   "com.apple.printcenter", "com.apple.Safari"] != ожидаемого возрастающего порядка
✘ rowOrderDoesNotChangeAsRemainingTimeChanges — 4 issues, в том числе строка 118:
  late  → ["com.tinyspeck.slackmacgap", "ru.keepcoder.Telegram", "com.apple.Safari"]
  early → ["ru.keepcoder.Telegram", "com.tinyspeck.slackmacgap", "com.apple.Safari"]
✘ rowOrderDoesNotChangeWhenARuleIsDisabledOrItsAppExits — 3 issues
✘ Test run with 13 tests in 1 suite failed after 0.003 seconds with 9 issues.
```

Обрати внимание на строку 118: она сравнивает `late` с `early`, а не с литералом. Это
утверждение о **стабильности**, и оно падает само по себе, независимо от того, какой порядок
считать правильным.

**Мутация 2 — реализация, у которой ключ правильный, а стабильность нет.** Сортировка по
`bundleIdentifier`, но строки с истёкшим остатком поднимаются наверх:

```swift
func expired(_ row: PopoverRow) -> Int { (row.soonestRemaining ?? 1) == 0 ? 0 : 1 }
```

Результат:

```
✔ Test rowsSortByBundleIdentifierAscending() passed after 0.001 seconds.
✔ Test rowOrderDoesNotChangeWhenARuleIsDisabledOrItsAppExits() passed after 0.001 seconds.
✘ Test rowOrderDoesNotChangeAsRemainingTimeChanges() recorded an issue at :118:9:
  late  → ["com.tinyspeck.slackmacgap", "ru.keepcoder.Telegram", "com.apple.Safari"]
  early → ["com.apple.Safari", "com.tinyspeck.slackmacgap", "ru.keepcoder.Telegram"]
✘ Test run with 13 tests in 1 suite failed after 0.002 seconds with 2 issues.
```

Это и есть требуемое доказательство: тест на ключ (№1) **проходит** на нестабильной реализации,
а ловит её только тест №2. Один ключ проверить недостаточно, и тесты это учитывают.

Как устроены новые тесты, чтобы это работало:

1. `rowsSortByBundleIdentifierAscending` — пять правил, и каждый прежний вход спорит с ответом:
   `safari` выключен (прежде уходил последним), `printCenter` не запущен (прежде уходил после
   запущенных), у `telegram` наименьший остаток (прежде уходил первым). Пара
   `com.apple.TextEdit` / `com.apple.printcenter` дополнительно запирает **обычное строковое**
   сравнение: регистронезависимое или локализованное дало бы обратный порядок.
2. `rowOrderDoesNotChangeAsRemainingTimeChanges` — те же правила и те же сессии при `now: t(0)`
   и `now: t(200)`. Дедлайны подобраны так, что во второй момент оба остатка схлопываются в
   ноль, то есть **относительный порядок по остатку реально меняется**, и на прежней реализации
   строки переставлялись. Сравнение идёт `late` против `early`, а не против литерала. Отсчёт
   действительно сдвинулся, и это утверждается отдельно:
   `early → [nil, 100, 50]`, `late → [nil, 0, 0]`.
3. `rowOrderDoesNotChangeWhenARuleIsDisabledOrItsAppExits` — базовая модель и две производные,
   каждая отличается от неё **ровно одним входом**: у `safari` щёлкнут тумблер, либо `safari`
   вышел (его сессия убрана). Обе сравниваются с базовым порядком. Дополнительно утверждается,
   что вход действительно изменился (`isEnabled == false`, `instances.isEmpty == true`), — иначе
   тест был бы вакуумным.

## Доказательства валидации

| Команда | Результат | Вывод |
|---|---|---|
| `swift package clean && swift build` | EXIT=0 | `Build complete! (8.50s)`, `warning:` — **0 строк** |
| `swift package clean && swift build -c release` | EXIT=0 | `Build complete! (8.53s)`, `warning:` — **0 строк** |
| `swift test` | EXIT=0 | `Test run with 82 tests in 8 suites passed after 0.143 seconds.`, `✘` — 0, `warning:` — 0 |
| `./scripts/check-forbidden.sh` | EXIT=0 | `OK: запрещённых конструкций не найдено` |
| `./build.sh` | EXIT=0 | `codesign --verify --strict` пройден; `designated requirement: identifier "com.svvoff.terminator" and certificate leaf = H"74d582911cd0b2c7ff3961af4bb0561efd6a8f24"` |

Счётчики `warning:` считались как `grep -c 'warning:'` по полному логу каждой команды, а не на
глаз. Обе сборки — после `swift package clean`, то есть полные, а не инкрементальные (release
компилирует три модуля целиком под WMO).

Три новых теста в прогоне поимённо:

```
✔ Test rowsSortByBundleIdentifierAscending() passed after 0.051 seconds.
✔ Test rowOrderDoesNotChangeAsRemainingTimeChanges() passed after 0.051 seconds.
✔ Test rowOrderDoesNotChangeWhenARuleIsDisabledOrItsAppExits() passed after 0.051 seconds.
```

Четыре вычеркнутых в прогоне не встречаются вовсе (грепом по логу: ни одной строки с
`rowsSortAscendingByRemainingTime`, `rulesWithNoRunningInstance`, `disabledRulesSortLast`,
`equalRemainingTimesBreakTie`).

**Число тестов: 83 → 82.** Минус четыре, плюс три. Сьютов по-прежнему 8. Сьют «Вью-модель
поповера» — 13 тестов.

## Acceptance criteria (амендмент 7)

| Критерий | Статус | Чем подтверждён |
|---|---|---|
| Порядок — `bundleIdentifier` по возрастанию | выполнен | `rowsSortByBundleIdentifierAscending` |
| Ни `sortRank`, ни бакетов, ни вторичного ключа | выполнен | дифф: `precedes` и `sortRank` удалены; греп по `Sources`/`Tests` даёт ноль вхождений `sortRank` и `precedes` |
| Экземпляры внутри строки — по `SessionKey` | выполнен | строка `PopoverViewModel.swift:41` не тронута; `ruleWithTwoRunningInstancesYieldsTwoRemainingTimes` (`instances.map(\.pid) == [501, 777]`) зелёный |
| Не по имени приложения | выполнен | имя в `TerminatorCore` не существует вовсе; `PopoverRow` его не несёт |
| Четыре теста вычеркнуты, три добавлены | выполнен | таблица выше, поимённо |
| 82 теста | выполнен | `Test run with 82 tests in 8 suites passed` |
| Ноль `warning:` в debug и release | выполнен | `grep -c 'warning:'` = 0 на обоих полных логах |
| Формат `config.json` не изменён | выполнен | `ConfigFormat`, `ConfigStore`, модель правил не тронуты; дифф касается только вью-модели и её тестов |
| Пункт 13 чеклиста (порядок не меняется от тика, запуска/выхода, тумблера) | **требует человека** | см. «Не запускалось» |

## Не запускалось

**Приложение не запускалось** — пакет это прямо запрещает, и раунд в этом не нуждается:
сортировка живёт в чистом ядре и полностью покрыта юнит-тестами.

Человеку остаётся пункт 13 чеклиста в его переписанной амендментом 7 форме — открыть поповер и
убедиться глазами, что порядок строк не меняется:

1. пока тикает отсчёт (подержать поповер открытым минуту с идущим отсчётом);
2. когда наблюдаемое приложение запускается и когда выходит;
3. когда щёлкается тумблер правила — строка должна остаться под курсором.

Дополнительно стоит взглянуть на видимое следствие, о котором автор предупреждён: порядок
выглядит произвольным, потому что сортируется bundle id, а на первой строке написано имя
приложения.

Остаточный риск низкий: все три пункта — ровно то, что утверждают три новых теста, и вью
(`PopoverView`) рисует порядок, который ему дали, без собственной сортировки.

## Проверка скоупа

```
$ git status --porcelain
 M Sources/TerminatorCore/PopoverViewModel.swift
 M Tests/TerminatorCoreTests/PopoverViewModelTests.swift
 M docs/ai/handoff/current-task-packet-popover.md
 M docs/product/backlog/tasks/in-progress/TASK-006-menu-bar-popover.md

$ git diff --stat Sources/TerminatorCore/PopoverViewModel.swift Tests/TerminatorCoreTests/PopoverViewModelTests.swift
 Sources/TerminatorCore/PopoverViewModel.swift      |  36 +++----
 .../PopoverViewModelTests.swift                    | 120 ++++++++++++++-------
 2 files changed, 97 insertions(+), 59 deletions(-)
```

Изменены исполнителем ровно два файла — те два, что разрешены пакетом, плюс этот отчёт.
`current-task-packet-popover.md` и карточку TASK-006 правил оркестратор до начала раунда;
исполнитель их не трогал. HEAD — `0775d01`.

Запрещённые зоны не тронуты: `Sources/Terminator/` (вью, `PopoverModel`, резолв имён,
валидатор панели, лог-строка раунда 5), `Sources/TerminatorAppKit/`, `Package.swift`,
`Packaging/Info.plist`, `build.sh`, подпись, keychain, путь quit, Apple Events, расчёт дедлайна,
модель правил, `ConfigStore`, `ConfigFormat`, код учёта фокуса (TASK-007). В `~/Library/`
ничего не писалось. Приложение не запускалось. `swift run` не вызывался.

Третий файл не понадобился.

## Риски

- **Низкий, косметический.** Порядок «по bundle id» выглядит произвольным относительно того,
  что читает глаз, — автор об этом предупреждён и цену принял (амендмент 7).
- `soonestRemaining` остался публичным свойством, у которого больше нет потребителя в
  продакшн-коде: он вычисляется только тогда, когда его спрашивают, поэтому стоимость нулевая,
  но формально это API без пользователя. Удалять его этим раундом не стал: это потребовало бы
  правки уцелевшего теста, который пакет не называл. Решение — за оркестратором.
- Сортировка в конструкторе `PopoverViewModel` теперь одна строка без именованного компаратора.
  Если когда-нибудь появится второй ключ, его придётся вводить осознанно — что и есть цель
  амендмента.

## Незавершённое и follow-up

Ничего незавершённого в границах пакета. Возможный follow-up (решает оркестратор): удалять ли
`PopoverRow.soonestRemaining` вместе с проверяющим его `#expect` в
`ruleWithTwoRunningInstancesYieldsTwoRemainingTimes` — это уменьшило бы число тестов не по
формуле «минус четыре, плюс три», поэтому в этот раунд не вносилось.
