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

Запись **TASK-001** (спайк подписи, согласия Apple Events и вежливого quit, ACCEPT 2026-08-27)
вытеснена в `archive/2026-08.md` при добавлении записи TASK-002: журнал перешёл ориентир в 400
строк. Её выводы живут в findings §4, §5, §6 — за транскриптами ходить в архив.

---

## 2026-08-27 — TASK-002 — SwiftPM-пакет, сборка бандла, подпись, череп в меню-баре — ACCEPT

**Что сделано.** Появился первый продуктовый код: `Package.swift` с тремя таргетами,
`Packaging/Info.plist` из девяти ключей, `build.sh`, собирающий и подписывающий
`build/Terminator.app`, и меню-бар-аксессуар с черепом DEC-009, нарисованным кодом. Три раунда
исполнения, каждый отревьюен отдельным ходом.

**Валидация.** L0 закрыл исполнитель, всё перепроверено оркестратором своими прогонами.
Ручной чеклист выполнил автор на своей машине: два запуска бандла плюс третий после амендмента 2.

**Решения и отклонения по ходу — три, все зафиксированы в карточке амендментами.**

1. cdhash-гейт, написанный по букве пакета, не сработал — исправлен исполнителем, отклонение
   принято (транскрипт ниже).
2. Гейт переписан с блоклиста на fail-closed позитивную проверку (амендмент 1) — разрешение
   пользователя на зону 1 получено явно.
3. Состояние глаз глифа поднято в `App` и переключается кнопкой (амендмент 2): Review trigger
   DEC-009 спрашивает про различимость **на фоне меню-бара**, а раунд 1 отвечал на этот вопрос
   образцами в поповере, то есть отвечал на другой.

**Имена, которые нужны следующим карточкам.** Адаптерный таргет — `TerminatorAppKit`, его
публичное API сегодня: `enum MenuBarGlyphEyes { case idle, active }` и
`func menuBarSkullImage(eyes:) -> NSImage`. Константы логирования — `TerminatorLog` в
`Sources/TerminatorCore/LoggingIdentity.swift`: `TerminatorLog.subsystem` =
`com.svvoff.terminator`, категории `TerminatorLog.Category.engine/.quit/.consent/.store/.focus/
.loginItem` со значениями `engine`, `quit`, `consent`, `store`, `focus`, `loginitem`. Шаблон
плиста — `Packaging/Info.plist`.

### Подпись переживает пересборку — designated requirement побайтово

Прогон A, односимвольная правка строкового литерала, прогон B, откат правки:

```
# прогон A
designated => identifier "com.svvoff.terminator" and certificate leaf = H"74d582911cd0b2c7ff3961af4bb0561efd6a8f24"
CDHash=b87d3ddb4a8d4bfc80e311679b268bbd7d698b4f

# прогон B, после правки одного символа в строковом литерале
designated => identifier "com.svvoff.terminator" and certificate leaf = H"74d582911cd0b2c7ff3961af4bb0561efd6a8f24"
CDHash=a3d5f0d310cdbfbabedd13aecaf028c1060ee23c

DR: ПОБАЙТОВО ОДИНАКОВ (cmp exit 0)
CDHash: различается — контроль настоящий
```

Контроль по CDHash здесь не украшение: без него тест проходит и тогда, когда правка не изменила
бинарь, то есть доказывает ничто.

### Гейт по букве пакета не сработал — почему

Пакет требовал снять префикс `designated => ` **с начала строки**. Прогон
`./build.sh --adhoc-control` вышел с нулём:

```
--- cdhash guard ---
designated requirement: # designated => cdhash H"4dee3f67c68aa74c1fb245d80c83951e40f2b1a4"
--- codesign --verify --strict (терминальный шаг) ---
EXIT=0
```

Перепроверено оркестратором на другом ad-hoc бандле:

```
сырое:             [# designated => cdhash H"10e8914b2d6adbdf7101a705d1af283b51ed471f"]
strip-по-началу:   [# designated => cdhash H"10e8914b…"]   → гейт ПРОПУСТИЛ бы
strip-по-подстроке:[cdhash H"10e8914b…"]                   → гейт срабатывает
```

Ad-hoc DR печатается с ведущим маркером комментария, сертификатный — без. Ушло в findings §6.

### Одной верификации мало

Тот же ad-hoc бандл:

```
codesign --verify --strict build/Terminator.app; echo EXIT=$?
EXIT=0
```

Верификация подтверждает целость печати и молчит о том, кто подписал. Отсюда гейт стоит **до**
неё, а не вместо.

### Гейт после амендмента 1 — fail-closed

```
$ ./build.sh --self-test-guard
ожидаемый designated requirement: identifier "com.svvoff.terminator" and certificate leaf = H"74d5…"
  OK   ad-hoc подпись (cdhash) -> reject
  OK   чужой сертификат (другой хеш листа) -> reject
  OK   уехавший CFBundleIdentifier -> reject
  OK   ожидаемый текст дословно -> accept
self-test: 4 из 4 вердиктов верны                                    EXIT=0

$ ./build.sh --adhoc-control                                          EXIT=1
build.sh: DESIGNATED_REQUIREMENT_MISMATCH: … получено: cdhash H"10e8914b…"
  (строки `--- codesign --verify --strict ---` в выводе нет: гейт стоит раньше)

$ ./build.sh                                                          EXIT=0
$ ./build.sh --bogus-flag                                             EXIT=2
```

Отказ гейта на чужом сертификате доказан синтетическими строками, **без подписи чужим
сертификатом**: `Apple Development: Vladimir Voytsekhovskiy (63PZ483Z52)` не использовался,
не экспортировался, не изменялся и не удалялся.

### Верификация зависит от trust-домена — измерено случайно

Один и тот же бандл, неизменный на диске, в двух оболочках подряд:

```
# оболочка без доступа к keychain (песочница)
$ security find-identity -v -p codesigning
     0 valid identities found
$ codesign -d -r- build/Terminator.app
designated => identifier "com.svvoff.terminator" and certificate leaf = H"74d5…"   # работает
$ codesign --verify --strict build/Terminator.app
build/Terminator.app: CSSMERR_TP_NOT_TRUSTED
EXIT=1

# обычная оболочка, тот же файл, минутами позже
$ security find-identity -v -p codesigning
     2 valid identities found
$ codesign --verify --strict --verbose=2 build/Terminator.app
build/Terminator.app: valid on disk
build/Terminator.app: satisfies its Designated Requirement
EXIT=0
```

`Terminator Dev` — самоподписанный корень, доверенный через пользовательский домен:
`security dump-trust-settings` показывает у него 9 настроек `kSecTrustSettingsResultTrustRoot`.
Ушло в findings §6. Практическое следствие: агент, собирающий в песочнице, получит красную
сборку на исправном бандле, и падение будет выглядеть как дефект подписи.

### Ручной чеклист — выполнил автор

```
TASK-002 activationPolicy: NSApplicationActivationPolicy(rawValue: 1) (rawValue 1) bundleIdentifier: com.svvoff.terminator
```

Строка печатается из `.onAppear` вью **внутри** поповера, поэтому её появление доказывает и то,
что череп был виден в меню-баре, и то, что поповер открылся. `rawValue 1` = `.accessory`.

Наблюдения автора:

- череп читается в меню-барном размере, **в светлой и в тёмной теме**; геометрия DEC-009
  принята и остаётся;
- кнопка «Switch to active» меняет глиф **в самом меню-баре** — лейбл `MenuBarExtra` реактивен,
  прямая форма `Image(nsImage:)` без `.id(…)` и пересозданий сцены. Ушло в findings §8: раздел
  до этого говорил, какой **тип** лейбла переживает, но не говорил, перерисовывается ли он;
- кнопка Quit закрывает приложение, пункт исчезает из меню-бара. Сигналами не пользовались.

### Правка оркестратора inline

После раунда 3 оркестратор поправил один комментарий в `PlaceholderView.swift`: он утверждал,
что пара образцов в поповере закрывает Review trigger DEC-009 — ровно то, что амендмент 2
опроверг. Правка только в комментарии; после неё `swift build -c release`, `./build.sh`,
`check-forbidden.sh` и `codesign --verify --strict` прогнаны заново, все зелёные.
