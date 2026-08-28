# Журнал исполнения — текущая веха

Одна запись на принятую задачу. Здесь же лежат **сырые транскрипты измерений**: TASK-001 прямо
требует, чтобы выводы команд и тексты диалогов согласия попадали сюда, а в
`docs/product/recon/macos-findings.md` уходили только выводы. Findings читает каждая
последующая задача, поэтому он обязан оставаться коротким; журнал — нет.

Из этого следует правило ротации: журнал **не** обязан быть компактным, но обязан быть
навигируемым. Когда `latest.md` перестаёт читаться (ориентир — 400 строк) или закрывается
веха, записи переезжают в `archive/YYYY-MM.md`, а здесь остаются только записи текущей вехи.
Архив не читается по умолчанию.

Резюме принятой задачи в одну строку живёт в `../execution-state.md` — журнал не является
маршрутизирующей поверхностью и не читается для выбора следующей задачи.

Формат записи:

```markdown
## YYYY-MM-DD — TASK-XXX — <заголовок> — ACCEPT

- Что сделано: 1–3 строки.
- Валидация: команды и результаты; для manual-checklist — кто выполнял и что увидел.
- Решения и отклонения: что пришлось решить по ходу; что эскалировалось.
- Транскрипты: ниже, под свёрткой, дословно.
```

---

## Ротация

В `archive/2026-08.md` вытеснены две записи, обе по правилу 400 строк:

- **TASK-001** — спайк подписи, согласия Apple Events и вежливого quit (ACCEPT 2026-08-27).
  Выводы живут в findings §4, §5, §6.
- **TASK-002** — SwiftPM-пакет, сборка бандла, подпись, череп в меню-баре (ACCEPT 2026-08-27).
  Выводы живут в findings §6 и §8, а форма сборки — в `current-state.md`.

За дословными транскриптами обеих — в архив.

---

## 2026-08-27 — TASK-003 — модель правила и долговечное хранилище конфига — ACCEPT

**Что сделано.** Доменная модель (`Rule`, `Limit`, `RuleConfig`), версионированный
человекочитаемый JSON-формат, общий хелпер долговечной записи `writeDurably(_:to:)` и
`ConfigStore` с читаемым карантином и стартовой уборкой хвостов. Первый тестовый таргет в
репозитории: 22 синхронных теста в четырёх сьютах, 0.09 с, без единого sleep. UI, движка,
наблюдателей и focus-хранилища не появилось — таргеты `Terminator` и `TerminatorAppKit` не
тронуты вовсе.

**Валидация.** Профиль `[swift-build, swift-test]`, `manual-checklist` в карточке нет — человеку
проверять нечего. Все прогоны перепроверены оркестратором своими командами, а не приняты по
отчёту:

| Команда | Исполнитель | Оркестратор |
|---|---|---|
| `swift build` | exit=0, 0 `warning:` | exit=0, 0 `warning:` |
| `swift build -c release` | exit=0, 0 `warning:` | exit=0, 0 `warning:` |
| `swift test` | 22 теста / 4 сьюта, 0.094 с | exit=0, 22 теста / 4 сьюта, 0.089 с |
| `swift test -c release` | 22 теста / 4 сьюта, 0.087 с | exit=0, 22 теста / 4 сьюта, 0.107 с |
| `scripts/check-forbidden.sh` | OK | OK |
| `scripts/verify-docs.sh` | — | 0 ошибок, 0 предупреждений |

Следов в реальной системе не осталось: `~/Library/Application Support/com.svvoff.terminator`
не существует, `~/Library/LaunchAgents` не открывался, временных каталогов тестов в `TMPDIR`
не осталось.

Четыре запрета, которые грепом не ловятся, проверены чтением кода: `privacy: .public` стоит на
всех восьми местах логирования без исключений; ни `Date()`, ни `SuspendingClock`, ни
`ContinuousClock`, ни `async`, ни акторов в `Sources/TerminatorCore/` нет вовсе (грep пуст —
единственное совпадение это слово `async` внутри доккомментария); кэширования pid здесь нет,
потому что процессов здесь нет.

**Решения и отклонения.** Шесть отклонений от пакета, все заявлены исполнителем, ни одно не
скрыто. Приняты все шесть:

1–2. **Байты pretty-print не совпали с эталоном пакета** — это зона 6, поэтому проверено
отдельно и независимо (см. транскрипт ниже). Эталон пакета показывал `limit` в одну строку,
`JSONEncoder` разворачивает вложенный объект на четыре; пустой `rules` он пишет как `{` +
пустая строка + `}`, а не `{}`. **Ключи, значения, порядок и типы совпадают с утверждённым
контрактом полностью** — расходится только расстановка переносов, и она принадлежит
`JSONEncoder`. Свернуть её можно было бы только собственным сериализатором; цена — свой
JSON-writer в ядре ради косметики файла, который и так правится руками. Принято как есть;
**канонические байты — те, что в транскрипте ниже, а не эталон в пакете**.

3. **Греп критерия 11 на `Bundle.main.bundleIdentifier` не пуст по всему дереву:** одно
вхождение в `Sources/Terminator/PlaceholderView.swift:122`, от TASK-002. Это диагностическая
строка, которая **показывает** факт findings §7 (`bundleIdentifier == nil` у голого
SwiftPM-бинаря), а не выводит из него путь; лежит в таргете приложения, для исполнителя это
запрещённая зона, и он её справедливо не тронул. Критерий 11 существует ради «путь не выводится
из бандла», и это выполнено: в `Sources/TerminatorCore`, `Tests` и `Package.swift` греп пуст.
Отдельной карточки не заводится — плейсхолдер уходит целиком в TASK-006.

4. **`save(_ config:)` вместо `save()`** — форма с аргументом не требует публичного сеттера у
`config`, который позволил бы памяти разъехаться с диском. Лучше, чем в пакете.

5. **Две причины отказа лимита** (`.limitIsNotWholeMinutes` и `.limitMinutesOutOfRange`)
вместо одной: в баннере TASK-006 это две разные жалобы. Второго case у `Limit` не появилось —
запрет «не строить будущее» не нарушен.

6. **`schemaVersion` меньше текущей отображается в `.undecodableBytes`**, а не в четвёртый case
карантина: схемы v0 никогда не существовало, и заводить под неё отдельную причину — то самое
построение будущего, которое карточка запрещает.

Эскалаций нет. Ни DEC-001, ни DEC-005 не задеты; ни один факт findings не опровергнут, §14
подтверждён прямым чтением лога (`log show` без `--info` вернул все строки без единого
`<private>`).

**Замечено при ревью, менять не просил.** Если `fsync` каталога упадёт уже после успешного
`rename`, `writeDurably` бросит, и `save` не обновит конфиг в памяти — на диске будет новая
версия, в памяти прежняя. Отказ здесь честнее успеха (незасинхроненный rename не гарантирован),
а расхождение чинится следующей загрузкой. Записано, чтобы не выглядело сюрпризом.

<details><summary>Транскрипт: реальные байты config.json, снятые оркестратором независимо</summary>

Проверка сделана не пересказом отчёта: исходники ядра собраны отдельным бинарём мимо пакета
(`swiftc -swift-version 6 Sources/TerminatorCore/*.swift scratch/main.swift`), который зовёт
настоящий `ConfigStore.save` во временный каталог.

```
─── config.json (два правила) ───
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
─── config.json (пустой конфиг) ───
{
  "rules" : {

  },
  "schemaVersion" : 1
}
─── ConfigStore.defaultDataDirectory ───
/Users/as.sorokin/Library/Application Support/com.svvoff.terminator
```
</details>

### Формат на диске — контракт схемы v1

Это запись, ради которой карточка требовала документирования: TASK-006, TASK-007 и TASK-008
берут её отсюда, не читая исходники.

- **Путь:** `~/Library/Application Support/com.svvoff.terminator/config.json`.
  Публично: `ConfigStore.defaultDataDirectory`, `ConfigStore.configFileName`.
  Каталог создаётся с промежуточными **при первой записи**, не при загрузке.
- **Идентификатор:** `TerminatorIdentity.bundleIdentifier` — единственное вхождение литерала
  `"com.svvoff.terminator"` в `Sources/`. Из него выведены подсистема логов, имя каталога и
  запрет правила-на-себя. Второй константы не заводить.
- **Корень:** `schemaVersion: Int` (сейчас `1`) и `rules` — **JSON-объект, ключ = bundle id**
  (не массив). Два правила на одно приложение невыразимы по форме файла.
- **Правило:** `limit` — тегированный объект `{ "kind": "constant", "limitSeconds": Int }`;
  `enabledAt` — строка ISO 8601 **без долей секунды** (`"2026-08-27T13:00:00Z"`), либо ключ
  отсутствует, либо `null` — и то, и другое значит «выключено». Отдельного булева флага нет
  нигде (DEC-001).
- **Диапазон `limitSeconds`:** кратные 60 от **60 до 28800** включительно, то есть 1…480 целых
  минут. Константа диапазона — `Limit.allowedMinutes`; редактор TASK-006 читает её, а не
  повторяет числа. Всё остальное роняет декод.
- **Кодирование:** `.prettyPrinted` + `.sortedKeys`, даты `.iso8601`. Повторная запись одного
  конфига побайтово идентична, и порядок ключей не зависит от порядка построения.
- **Неизвестные ключи** внутри известной версии игнорируются: чужое поле-комментарий в ручной
  правке не роняет конфиг в карантин.
- **Хелпер записи:** `public func writeDurably(_ bytes: Data, to destination: URL) throws` —
  temp `<имя>.sb-<uuid>` рядом с назначением (`O_WRONLY|O_CREAT|O_EXCL`, `0o644`) →
  `fcntl(F_FULLFSYNC)` на том же дескрипторе → `rename(2)` → `fsync` каталога. **Каталог
  назначения хелпер не создаёт** — это дело вызывающего. Ошибки — `DurableWriteError` с шагом
  и `errno`.
- **Уборка** хвостов (`.sb-`, `.tmp-`) ходит **только** по каталогу данных приложения и не
  рекурсивно. Расширять её на каталог назначения хелпера нельзя: TASK-008 пишет в
  `~/Library/LaunchAgents`, где лежат чужие файлы.
- **Карантин:** `ConfigStore.quarantine: ConfigLoadFailure?` — read-only состояние с тремя
  различимыми причинами (`.undecodableBytes(message:)`, `.rejectedRule(RuleRejected)`,
  `.schemaVersionFromTheFuture(found:supported:)`). В карантине `save` бросает
  `ConfigStoreError.quarantined` и не пишет ни байта; байты на диске остаются нетронутыми,
  конфиг в памяти — прежним. Снимается только успешной перезагрузкой. TASK-006 обязана это
  отрисовать: без баннера отказ полностью бессимптомен (DEC-004 не оставляет канала
  уведомлений).

---

## 2026-08-28 — TASK-009 — Спайк: нужно ли согласие Apple Events для quit на других приложениях — ACCEPT

(Измерения проведены 2026-08-27; сессия шла через полночь, приёмка 28-го — как и на TASK-001.)

**Маршрут: inline (оркестратор), совместно с оператором.** Карточка несёт только
`manual-checklist`, и каждое испытание упирается в интерактивный диалог согласия и в живое
приложение, которое надо увидеть закрывшимся. Делегировать это нельзя ни субагенту, ни
воркфлоу: некому нажать `Allow` и некому увидеть смерть — исполнитель молча отчитался бы об
успехе. Та же причина, по которой CLAUDE.md запрещает делегировать TASK-001.

**Машина:** macOS **26.6.2 (25G83)**, arm64. TASK-001 мерил на 26.5.2 (25F84), поэтому строка
TextEdit здесь — не дубликат, а воспроизведение на другой версии ОС.

**Что сделано.** Allow-list пробника TASK-001 расширен с одного идентификатора до пяти;
параметра цели в командной строке не заведено (карточка называет его прямым основанием для
отказа). Подопытный выбирается состоянием машины: ровно одно приложение из списка должно быть
запущено, ноль и больше одного — отказ с перечислением увиденного. Пять подопытных, выбранных
оператором, по три состояния согласия и отрицательному контролю каждый.

### Ответ на вопрос карточки

**Согласия на пути quit нет вообще. Семнадцать отправок — семнадцать смертей.**

| Подопытный | Сторона | Sandbox | Дистрибуция | Scriptable | не спрашивали | запрещено | разрешено |
|---|---|---|---|---|---|---|---|
| TextEdit | Apple | да | система | да | 0.254 с | 0.259 с | 0.255 с |
| Calculator | Apple | да | система | **нет** | 0.258 с | 0.258 с | 0.257 с |
| VLC | третья | **нет** | прямая | да | 0.257 с | 0.257 с | 0.260 с |
| Todoist | третья | да | **App Store** | нет | 0.515–0.770 с | 0.517 с | 0.517 с |
| Obsidian | третья | нет | прямая | нет | 0.262 с | 0.257 с | 0.253 с |

`AESendMessage` вернул `noErr` за 0.003–0.007 с во всех семнадцати отправках, включая все
отправки при **явно запрещённом** согласии. Отрицательный контроль на каждого подопытного —
запущен, ничего не отправлено, жив через 20 с.

Ни одно испытание не засчитано без сброса, проверенного на `-1744` непосредственно перед ним.
Все запуски пробника — через `run-probe.sh` (LaunchServices); прямого exec из
`Contents/MacOS/` нет нигде.

### Что это значит для бэклога

- **TASK-005 незачем существовать в текущем виде.** Пре-варминг, состояние согласия на
  приложение и диплинк в System Settings решают задачу, которой нет: греть нечего и обходить
  нечего. Это рекомендация от измерения — карточка не правилась.
- **DEC-002** трактует `-1743` как немедленно терминальное на пути quit — случай не возникает.
- **DEC-004** опасается диалога согласия в момент закрытия — не возникает.
- «Only permission cost is Apple Events» в EPIC-02, DEC-005, DEC-006 завышает цену, которая
  для ограничителя равна нулю.

### Второе измерение: findings §4 опровергнут

`NSWorkspace.runningApplications` **отстаёт от ядра**, и §4 с его «никогда не расходились
более чем на 16 мс» верен только для TextEdit. У Todoist:

| Испытание | `sysctl` | `NSWorkspace` | Расхождение |
|---|---|---|---|
| не спрашивали | 0.770 с | не увидел за 20 с | **> 19 с** |
| не спрашивали, повтор | 0.515 с | 0.522 с | 7 мс |
| запрещено | 0.517 с | 2.047 с | **1.53 с** |
| разрешено | 0.517 с | 1.034 с | **0.52 с** |

У остальных четырёх за двенадцать отправок расхождение не превысило 16 мс. Todoist умирает и
вдвое медленнее: ~0.52 с против кластера 0.253–0.262 с. **Для TASK-004: смерть подтверждается
на ядре, не на списке рабочего пространства.**

### Наблюдение, оставленное необъяснённым

В первом испытании Todoist новый процесс приложения появился **через 31 с** после quit.
Оператор его не запускал (спрошено прямо и подтверждено). Агента автозапуска нет ни в
`~/Library/LaunchAgents`, ни в `/Library/LaunchAgents`, ни в `launchctl list`.

**Не воспроизвелось.** Два контролируемых повтора с поллером `ps` каждые 0.5 с — 90 с и 120 с —
возврата не увидели вовсе. В том первом прогоне поллера не было, поэтому по имеющимся данным
**нельзя** сказать, вернулось приложение внутри окна наблюдения или после него. Записано как
предмет наблюдения для TASK-004, а не как свойство Todoist. Механизм не выяснялся: карточка
это прямо запрещает, а угаданный по поведению механизм — не находка.

### Побочные наблюдения

- **Electron-хелперы не пережили главный процесс.** У Obsidian было 4 процесса; после смерти
  главного `ps` не нашёл ни одного процесса из `Obsidian.app`. Вежливый quit увёл всё дерево.
- **Диалог согласия — один шаблон на всех пятерых**, снят скриншотами по каждому. Меняется
  только имя цели. Клиент называется по **имени файла бандла** («Probe»), а не `CFBundleName`;
  вторая строка — `NSAppleEventsUsageDescription` дословно. Шаблон обещает доступ к «documents
  and data» даже у **Calculator**, у которого документов нет: формулировка системная и к
  возможностям цели не адаптируется.
- Блокировка потока на диалоге: 1.264–16.196 с по семи диалогам. Подтверждает §5 — держать на
  этом потоке нечего, что нужно продукту.

### Отклонения от пакета

1. **`build-probe.sh`: строка `NSAppleEventsUsageDescription` переписана** с «…against
   TextEdit» на нейтральную к подопытному. Формально это шире, чем «только расширение
   allow-list», но строка **рендерится в диалоге дословно** и с пятью подопытными вводила бы
   оператора в заблуждение ровно в тот момент, когда он этот диалог читает и записывает.
2. **Испытание 3 на TextEdit прогнано дважды.** Первый `Allow` (noErr за 1.509 с) прошёл без
   захвата текста диалога; сброшен и перезапущен ради скриншота. Записан здесь, а не выброшен.
3. **Todoist прогнан пять раз вместо трёх** — два лишних прогона ушли на характеризацию
   расхождения и на опыт с возвращением.
4. **Строка `REFUSED: … found 0`** печатается новым guard-ом в середине наблюдения, уже после
   смерти подопытного. Ожидаемый шум, наблюдение при этом отрабатывает корректно.
5. **Ротация журнала:** запись TASK-002 вытеснена в архив, иначе `latest.md` ушёл бы далеко за
   ориентир в 400 строк.

### Найдено ревью (отдельным ходом, до чтения отчёта)

Три числа в первой редакции отчёта и findings не сошлись с сырыми данными; исправлены, вывод
карточки ни одним из них не задет:

- `tccutil reset` — было «девять раз», на деле **17** (по одному на отправку);
- диалогов согласия — было «семь» и список из восьми значений, на деле **11 поднято**, 10 с
  сохранившимся транскриптом; в списке не хватало Calculator (17.986 с) и VLC (16.873 с);
- findings §4 — «fourteen sends» против «twelve sends» двумя строками выше, в одном абзаце.
  Верно **twelve**.

Плюс два дефекта, оба записаны в отчёт:

- **транскрипт первого `Allow` на TextEdit перезаписан** — перезапуск испытания 3 писался `tee`
  в тот же файл. Числа (`noErr`, 1.509 с) живут только в прозе; сырой строки за ними нет;
- **`findSubject()` возвращает nil и на «ноль запущено», и на «больше одного»**, а
  `observeTermination` трактует nil как «исчезло». При двух запущенных подопытных наблюдение
  отрапортовало бы ложную смерть на 0.000 с. Ни одно измерение не задето — в каждой отправке
  стоит `found 0`, — но следующая карточка, взявшая пробник, должна это знать.

### Транскрипт

Полный сырой транскрипт всех испытаний. Файл поллера `ps` (180 строк одинаковых) не включён —
его переходы видны в записи `16-todoist-divergence`.

<details><summary>Семнадцать отправок quit, пять подопытных, дословно</summary>

```
── 01-textedit-negative-control
★ NEGATIVE CONTROL — TextEdit — 2026-08-27T15:31:49Z

── 02-textedit-trial1-reset-and-check
★ TRIAL 1 (never asked) — TextEdit — 2026-08-27T15:32:29Z
Successfully reset AppleEvents approval status for com.svvoff.terminator.probe
subject: com.apple.TextEdit pid=8867
status: -1744 (errAEEventWouldRequireUserConsent)
call blocked for: 0.029 s

── 03-textedit-trial1-quit
★ TRIAL 1 (never asked) — TextEdit — отправка quit — 2026-08-27T15:32:40Z
subject: com.apple.TextEdit pid=8867
AESendMessage: 0 (noErr)
AESendMessage blocked for: 0.006 s
sysctl(KERN_PROC_PID): pid 8867 gone after 0.254 s
NSWorkspace.runningApplications: gone after 0.262 s

── 04-textedit-trial2-deny
★ TRIAL 2 (denied) — TextEdit — 2026-08-27T15:33:23Z
Successfully reset AppleEvents approval status for com.svvoff.terminator.probe
subject: com.apple.TextEdit pid=24183
status: -1744 (errAEEventWouldRequireUserConsent)
call blocked for: 0.022 s
subject: com.apple.TextEdit pid=24183
status: -1743 (errAEEventNotPermitted)
call blocked for: 14.062 s

── 05-textedit-trial2-quit
★ TRIAL 2 (denied) — TextEdit — подтверждение запрета и отправка quit — 2026-08-27T15:34:11Z
subject: com.apple.TextEdit pid=24183
status: -1743 (errAEEventNotPermitted)
call blocked for: 0.024 s
subject: com.apple.TextEdit pid=24183
AESendMessage: 0 (noErr)
AESendMessage blocked for: 0.005 s
sysctl(KERN_PROC_PID): pid 24183 gone after 0.259 s
NSWorkspace.runningApplications: gone after 0.275 s

── 06-textedit-trial3-allow
★ TRIAL 3 (granted) — TextEdit — ПЕРЕЗАПУСК ради захвата текста диалога — 2026-08-27T15:36:15Z
Successfully reset AppleEvents approval status for com.svvoff.terminator.probe
subject: com.apple.TextEdit pid=35981
status: -1744 (errAEEventWouldRequireUserConsent)
call blocked for: 0.024 s
subject: com.apple.TextEdit pid=35981
status: 0 (noErr)
call blocked for: 16.196 s
### нажата кнопка: Allow

── 07-textedit-trial3-quit
★ TRIAL 3 (granted) — TextEdit — подтверждение гранта и отправка quit — 2026-08-27T15:37:03Z
subject: com.apple.TextEdit pid=35981
status: 0 (noErr)
call blocked for: 0.025 s
subject: com.apple.TextEdit pid=35981
AESendMessage: 0 (noErr)
AESendMessage blocked for: 0.003 s
sysctl(KERN_PROC_PID): pid 35981 gone after 0.255 s
NSWorkspace.runningApplications: gone after 0.262 s

── 08-calculator-control-and-trial1
★ SUBJECT 2 — Calculator (com.apple.calculator) — 2026-08-27T15:37:36Z
Successfully reset AppleEvents approval status for com.svvoff.terminator.probe
subject: com.apple.calculator pid=56168
status: -1744 (errAEEventWouldRequireUserConsent)
call blocked for: 0.035 s
subject: com.apple.calculator pid=56168
AESendMessage: 0 (noErr)
AESendMessage blocked for: 0.006 s
sysctl(KERN_PROC_PID): pid 56168 gone after 0.258 s
NSWorkspace.runningApplications: gone after 0.265 s

── 09-calculator-trial2-deny
★ SUBJECT 2 — Calculator — TRIAL 2 (denied) — 2026-08-27T15:38:43Z
Successfully reset AppleEvents approval status for com.svvoff.terminator.probe
subject: com.apple.calculator pid=69869
status: -1744 (errAEEventWouldRequireUserConsent)
call blocked for: 0.030 s
subject: com.apple.calculator pid=69869
status: -1743 (errAEEventNotPermitted)
call blocked for: 17.986 s
subject: com.apple.calculator pid=69869
status: -1743 (errAEEventNotPermitted)
call blocked for: 0.031 s
subject: com.apple.calculator pid=69869
AESendMessage: 0 (noErr)
AESendMessage blocked for: 0.004 s
sysctl(KERN_PROC_PID): pid 69869 gone after 0.258 s
NSWorkspace.runningApplications: gone after 0.267 s
### нажата кнопка: Don't Allow

── 10-calculator-trial3-allow
★ SUBJECT 2 — Calculator — TRIAL 3 (granted) — 2026-08-27T15:40:50Z
Successfully reset AppleEvents approval status for com.svvoff.terminator.probe
subject: com.apple.calculator pid=77629
status: -1744 (errAEEventWouldRequireUserConsent)
call blocked for: 0.023 s
subject: com.apple.calculator pid=77629
status: 0 (noErr)
call blocked for: 11.968 s
subject: com.apple.calculator pid=77629
status: 0 (noErr)
call blocked for: 0.021 s
subject: com.apple.calculator pid=77629
AESendMessage: 0 (noErr)
AESendMessage blocked for: 0.004 s
sysctl(KERN_PROC_PID): pid 77629 gone after 0.257 s
NSWorkspace.runningApplications: gone after 0.269 s
### нажата кнопка: Allow

── 11-vlc-control-and-trial1
★ SUBJECT 3 — VLC (org.videolan.vlc) — 2026-08-27T15:41:53Z
Successfully reset AppleEvents approval status for com.svvoff.terminator.probe
subject: org.videolan.vlc pid=88798
status: -1744 (errAEEventWouldRequireUserConsent)
call blocked for: 0.028 s
subject: org.videolan.vlc pid=88798
AESendMessage: 0 (noErr)
AESendMessage blocked for: 0.006 s
sysctl(KERN_PROC_PID): pid 88798 gone after 0.257 s
NSWorkspace.runningApplications: gone after 0.264 s

── 12-vlc-trial2-deny
★ SUBJECT 3 — VLC — TRIAL 2 (denied) — 2026-08-27T15:43:39Z
Successfully reset AppleEvents approval status for com.svvoff.terminator.probe
subject: org.videolan.vlc pid=97464
status: -1744 (errAEEventWouldRequireUserConsent)
call blocked for: 0.030 s
subject: org.videolan.vlc pid=97464
status: -1743 (errAEEventNotPermitted)
call blocked for: 16.873 s
subject: org.videolan.vlc pid=97464
status: -1743 (errAEEventNotPermitted)
call blocked for: 0.032 s
subject: org.videolan.vlc pid=97464
AESendMessage: 0 (noErr)
AESendMessage blocked for: 0.004 s
sysctl(KERN_PROC_PID): pid 97464 gone after 0.257 s
NSWorkspace.runningApplications: gone after 0.265 s
### нажата кнопка: Don't Allow

── 13-vlc-trial3-allow
★ SUBJECT 3 — VLC — TRIAL 3 (granted) — 2026-08-27T15:45:04Z
Successfully reset AppleEvents approval status for com.svvoff.terminator.probe
subject: org.videolan.vlc pid=4696
status: -1744 (errAEEventWouldRequireUserConsent)
call blocked for: 0.425 s
subject: org.videolan.vlc pid=4696
status: 0 (noErr)
call blocked for: 1.879 s
subject: org.videolan.vlc pid=4696
status: 0 (noErr)
call blocked for: 0.028 s
subject: org.videolan.vlc pid=4696
AESendMessage: 0 (noErr)
AESendMessage blocked for: 0.006 s
sysctl(KERN_PROC_PID): pid 4696 gone after 0.260 s
NSWorkspace.runningApplications: gone after 0.269 s

── 14-todoist-control-and-trial1
★ SUBJECT 4 — Todoist (com.todoist.mac.Todoist) — 2026-08-27T15:45:50Z
Successfully reset AppleEvents approval status for com.svvoff.terminator.probe
subject: com.todoist.mac.Todoist pid=27844
status: -1744 (errAEEventWouldRequireUserConsent)
call blocked for: 0.025 s
subject: com.todoist.mac.Todoist pid=27844
AESendMessage: 0 (noErr)
AESendMessage blocked for: 0.005 s
sysctl(KERN_PROC_PID): pid 27844 gone after 0.770 s
NSWorkspace.runningApplications: STILL LISTED after 20s

── 16-todoist-divergence
★ SUBJECT 4 — Todoist — ХАРАКТЕРИЗАЦИЯ РАСХОЖДЕНИЯ (повтор trial 1 с тройным наблюдением)
★ 2026-08-27 17:52:08 EET / 15:52:08Z
Successfully reset AppleEvents approval status for com.svvoff.terminator.probe
subject: com.todoist.mac.Todoist pid=33178
status: -1744 (errAEEventWouldRequireUserConsent)
call blocked for: 0.036 s
subject: com.todoist.mac.Todoist pid=33178
AESendMessage: 0 (noErr)
AESendMessage blocked for: 0.007 s
sysctl(KERN_PROC_PID): pid 33178 gone after 0.515 s
NSWorkspace.runningApplications: gone after 0.522 s

── 17-todoist-relaunch-test
★ SUBJECT 4 — Todoist — ОПЫТ НА ВОЗВРАЩЕНИЕ (условия прогона 1: запуск оператором)
★ 2026-08-27 18:16:12 EET
запущен оператором в 18:17:47, pid=16749
Successfully reset AppleEvents approval status for com.svvoff.terminator.probe
subject: com.todoist.mac.Todoist pid=16749
status: -1744 (errAEEventWouldRequireUserConsent)
call blocked for: 0.564 s
subject: com.todoist.mac.Todoist pid=16749
AESendMessage: 0 (noErr)
AESendMessage blocked for: 0.007 s
18:17:48  ps: 16749 
18:17:50  ps: —
### итог через 120 с: не вернулся

── 18-todoist-trial2-deny
★ SUBJECT 4 — Todoist — TRIAL 2 (denied) — 2026-08-27T16:20:55Z
Successfully reset AppleEvents approval status for com.svvoff.terminator.probe
subject: com.todoist.mac.Todoist pid=60652
status: -1744 (errAEEventWouldRequireUserConsent)
call blocked for: 0.017 s
subject: com.todoist.mac.Todoist pid=60652
status: -1743 (errAEEventNotPermitted)
call blocked for: 14.975 s
subject: com.todoist.mac.Todoist pid=60652
status: -1743 (errAEEventNotPermitted)
call blocked for: 0.012 s
subject: com.todoist.mac.Todoist pid=60652
AESendMessage: 0 (noErr)
AESendMessage blocked for: 0.004 s
sysctl(KERN_PROC_PID): pid 60652 gone after 0.517 s
NSWorkspace.runningApplications: gone after 2.047 s
### нажата кнопка: Don't Allow

── 19-todoist-trial3-allow
★ SUBJECT 4 — Todoist — TRIAL 3 (granted) — 2026-08-27T16:25:27Z
Successfully reset AppleEvents approval status for com.svvoff.terminator.probe
subject: com.todoist.mac.Todoist pid=68261
status: -1744 (errAEEventWouldRequireUserConsent)
call blocked for: 0.019 s
subject: com.todoist.mac.Todoist pid=68261
status: 0 (noErr)
call blocked for: 3.689 s
subject: com.todoist.mac.Todoist pid=68261
status: 0 (noErr)
call blocked for: 0.011 s
subject: com.todoist.mac.Todoist pid=68261
AESendMessage: 0 (noErr)
AESendMessage blocked for: 0.004 s
sysctl(KERN_PROC_PID): pid 68261 gone after 0.517 s
NSWorkspace.runningApplications: gone after 1.034 s

── 20-obsidian-control-and-trial1
★ SUBJECT 5 — Obsidian (md.obsidian) — 2026-08-27T16:26:08Z
Successfully reset AppleEvents approval status for com.svvoff.terminator.probe
subject: md.obsidian pid=87596
status: -1744 (errAEEventWouldRequireUserConsent)
call blocked for: 0.031 s
subject: md.obsidian pid=87596
AESendMessage: 0 (noErr)
AESendMessage blocked for: 0.004 s
sysctl(KERN_PROC_PID): pid 87596 gone after 0.262 s
NSWorkspace.runningApplications: gone after 0.265 s

── 21-obsidian-trial2-deny
★ SUBJECT 5 — Obsidian — TRIAL 2 (denied) — 2026-08-27T16:28:54Z
Successfully reset AppleEvents approval status for com.svvoff.terminator.probe
subject: md.obsidian pid=3614
status: -1744 (errAEEventWouldRequireUserConsent)
call blocked for: 0.031 s
subject: md.obsidian pid=3614
status: -1743 (errAEEventNotPermitted)
call blocked for: 11.672 s
subject: md.obsidian pid=3614
status: -1743 (errAEEventNotPermitted)
call blocked for: 0.022 s
subject: md.obsidian pid=3614
AESendMessage: 0 (noErr)
AESendMessage blocked for: 0.003 s
sysctl(KERN_PROC_PID): pid 3614 gone after 0.257 s
NSWorkspace.runningApplications: gone after 0.264 s
### нажата кнопка: Don't Allow

── 22-obsidian-trial3-allow
★ SUBJECT 5 — Obsidian — TRIAL 3 (granted) — 2026-08-27T16:47:43Z
Successfully reset AppleEvents approval status for com.svvoff.terminator.probe
subject: md.obsidian pid=59558
status: -1744 (errAEEventWouldRequireUserConsent)
call blocked for: 0.029 s
subject: md.obsidian pid=59558
status: 0 (noErr)
call blocked for: 1.264 s
subject: md.obsidian pid=59558
status: 0 (noErr)
call blocked for: 0.017 s
subject: md.obsidian pid=59558
AESendMessage: 0 (noErr)
AESendMessage blocked for: 0.004 s
sysctl(KERN_PROC_PID): pid 59558 gone after 0.253 s
NSWorkspace.runningApplications: gone after 0.260 s
```
</details>
