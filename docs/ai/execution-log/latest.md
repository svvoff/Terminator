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

## 2026-08-27 — TASK-001 — Спайк: подпись, согласие Apple Events, вежливый quit — ACCEPT

(Измерения проведены 2026-08-26; сессия шла через полночь, приёмка утром 27-го.)

- **Что сделано:** одноразовый пробник в `probes/task-001/` (bundle id
  `com.svvoff.terminator.probe`), четыре открытых вопроса измерены на macOS 26.5.2 (25F84),
  arm64. §4, §5, §6 findings переписаны; секция открытых вопросов заменена на settled.
  Три утверждения findings измерением **опровергнуты**.
- **Валидация:** профиль `manual-checklist`. Ручную часть выполнял пользователь: создание
  сертификата, Allow ×3, Don't Allow ×1, Delete в листе несохранённых изменений, скриншот
  System Settings. `verify-docs.sh` и `check-forbidden.sh` зелёные;
  `codesign --verify --strict` зелёный на всех четырёх сборках.
- **Решения и отклонения:** первый раунд измерений снят целиком — прямой exec из шелла
  оставлял ответственным процессом терминал, и TCC приписал согласие `claude`, а не пробнику.
  Исправлено запуском через LaunchServices. Шесть эскалаций в
  `handoff/current-execution-report.md`; ни одна карточка решения не правилась.
- **Транскрипты:** ниже.

### Поправка метода — почему первый раунд снят

Скриншот System Settings → Privacy & Security → Automation (от пользователя) показал запись
`claude` с включённым TextEdit и **ни одной записи пробника**. Значит согласие, полученное на
первом Allow, принадлежало терминалу.

```text
# первый раунд, прямой exec — сброс якобы не работает
$ tccutil reset AppleEvents com.svvoff.terminator.probe
Successfully reset AppleEvents approval status for com.svvoff.terminator.probe
$ probe check quit
  status: 0 (noErr)          <- ожидалось -1744; ТРАЙЛ ВОИД
$ tccutil reset AppleEvents com.svvoff.terminator.probe   # повтор
$ probe check quit
  status: 0 (noErr)          # и через 3 s тоже
$ sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db "select ..."
Error: authorization denied  # FDA не выдавался намеренно
$ log show --predicate 'subsystem == "com.apple.TCC"'
(пусто)

# после перезапуска TextEdit (новый pid 83211) — по-прежнему noErr,
# гипотеза «кеш на пару (клиент, целевой pid)» опровергнута

# исправление: запуск через LaunchServices
$ open -n -W -a Probe.app --args check quit
  status: -1744 (errAEEventWouldRequireUserConsent)   <- сброс наконец наблюдаем
```

`tccutil` был исправен всё время: он сбрасывал строки для `com.svvoff.terminator.probe`,
которых не существовало.

### Идентичность и подпись

```text
$ security find-identity -v -p codesigning
  1) 1C51384335AD4A242A4AEB6041E46D02C7724764 "Apple Development: Vladimir Voytsekhovskiy (63PZ483Z52)"
  2) 74D582911CD0B2C7FF3961AF4BB0561EFD6A8F24 "Terminator Dev"
     2 valid identities found

Terminator Dev: subject = issuer = CN=Terminator Dev, C=RU  (self-signed root)
                2026-08-26 → 2036-08-23
                X509v3 Extended Key Usage: critical / Code Signing
                keychain: login.keychain-db
```

Рабочий сертификат не использовался, не экспортировался и не изменялся.

### Вопрос 1 — четыре designated requirement дословно

```text
cert  tag A: designated => identifier "com.svvoff.terminator.probe" and certificate leaf = H"74d582911cd0b2c7ff3961af4bb0561efd6a8f24"
cert  tag B: designated => identifier "com.svvoff.terminator.probe" and certificate leaf = H"74d582911cd0b2c7ff3961af4bb0561efd6a8f24"
             -> байт-в-байт идентичны
adhoc tag A: designated => cdhash H"7775dbdb1bab980c292d03eaaad86e87d3a612af"
adhoc tag B: designated => cdhash H"9ee7d1a8259fe25b719f79657e30fed9de8dea2a"
             -> различны

CDHash cert  A 996b7efd795c53837debcb57432ac8a91d26dd0d   bin sha256 1653a20a…2178
CDHash cert  B 297cb17e23dd4f4231692b666d75b3f12894005e   bin sha256 83a4253f…9472
CDHash adhoc A 7775dbdb1bab980c292d03eaaad86e87d3a612af   bin sha256 bc94ab69…a97e6
CDHash adhoc B 9ee7d1a8259fe25b719f79657e30fed9de8dea2a   bin sha256 24c6787c…4fc97

codesign --verify --strict: "valid on disk" + "satisfies its Designated Requirement" — все 4
```

Сертификатная ветка:

```text
reset -> check quit     = -1744   [сброс проверен]
ask quit  -> Allow      = 0 noErr, поток блокирован 4.015 s
check quit              = 0 noErr
check wildcard          = 0 noErr
--- пересборка tag B, та же идентичность, БЕЗ сброса ---
check quit              = 0 noErr   -> ГРАНТ ВЫЖИЛ
```

Ad-hoc контроль:

```text
reset -> check quit     = -1744   [сброс проверен]
ask quit  -> Allow      = 0 noErr, поток блокирован 5.431 s
check quit              = 0 noErr
--- пересборка adhoc tag B ---
check quit              = 0 noErr   -> ГРАНТ ТОЖЕ ВЫЖИЛ  (findings §6 предсказывали потерю)
+25 s                   = 0 noErr   (вердикт не распадается со временем)
```

Перекрёстный тест — почему обе ветки выжили:

```text
# грант выдан ad-hoc сборке (DR = cdhash H"7775dbdb…")
# пересобрано СЕРТИФИКАТОМ (DR = identifier … certificate leaf H"74d5…", CDHash 996b7efd),
# которому в этом цикле грант НЕ выдавался:
check quit              = 0 noErr
-> TCC сопоставляет по bundle identifier, а не по designated requirement
```

### Вопрос 2 — отсутствующий NSAppleEventsUsageDescription

```text
Info.plist: NSAppleEventsUsageDescription отсутствует (подтверждено PlistBuddy)
reset -> check quit = -1744   [сброс проверен]

== identity ==
  NSAppleEventsUsageDescription: ABSENT
--- about to call AEDeterminePermissionToAutomateTarget(askUserIfNeeded: true) ---
  status: -1743 (errAEEventNotPermitted)
  call blocked for: 0.016 s          <- диалог НЕ появился
SURVIVED: the AEDeterminePermissionToAutomateTarget call returned
--- about to send the hand-rolled quit ---
  AESendMessage: 0 (noErr)
  AESendMessage blocked for: 0.000 s
SURVIVED: the AESendMessage call returned
  sysctl(KERN_PROC_PID): pid 52331 gone after 0.255 s

crash reports за последний час: нет
log show 'eventMessage CONTAINS "terminator.probe"': пусто
```

Ключ возвращён на место; `codesign --verify --strict` после восстановления зелёный.

### Вопрос 3 — hand-rolled quit против реального приложения

```text
sendMode: kAENoReply | kAEDoNotPromptForUserConsent (0x20001)
timeout:  kAEDefaultTimeout (-1)      # kAENormalTimeout в SDK НЕ существует

Trial A — TextEdit без несохранённого документа, pid 62402
  AESendMessage: 0 (noErr), блокировал 0.003 s
  sysctl(KERN_PROC_PID):            gone after 0.252 s
  NSWorkspace.runningApplications:  gone after 0.267 s     # расхождение 15 мс

Trial B — TextEdit с несохранённым документом, pid 77745
  AESendMessage: 0 (noErr), блокировал 0.007 s   <- НЕ блокируется, пока висит лист
  sysctl:      STILL ALIVE after 20s
  NSWorkspace: STILL LISTED after 20s
  ещё живо в 16:26:38 — через 6 мин 19 с после отправки
  send #2: 0 (noErr), 0.006 s   — приложение живо
  send #3: 0 (noErr), 0.006 s   — приложение живо
  оператор нажал Delete -> приложение закрылось
```

Оператор сообщил, что диалог сохранения был один; стакаются ли листы при повторных отправках,
достоверно не наблюдалось.

### Вопрос 4 — pre-warming, Deny, wildcard, мёртвый pid

```text
промпт с ФОНОВОЙ очереди появляется; блокирует только вызывающий поток; дедлоков нет
блокировки по трайлам: 147.968 s, 4.015 s, 5.431 s, 7.212 s

Allow                     -> 0 noErr
Deny                      -> -1743 errAEEventNotPermitted, блокировал 7.212 s
повторный ask после Deny  -> -1743, блокировал 0.023 s      <- больше не спрашивает

состояние      aevt/quit   wildcard
без гранта     -1744       -1744
с грантом       0 noErr     0 noErr
после отказа   -1743       -1743
мёртвый pid    -600        -600      (pid 62402, смерть подтверждена через sysctl)

грант пережил закрытие и перезапуск самой цели (новый pid) -> 0 noErr
```

### Quit не требует согласия — три трайла и негативный контроль

```text
состояние перед отправкой     AESendMessage      цель закрылась
никогда не спрашивали (-1744) 0 noErr, 0.007 s   да, 0.258 s
отказано (-1743)              0 noErr, 0.005 s   да
отказано (-1743), повтор      0 noErr, 0.011 s   да, 0.254 s

негативный контроль: нетронутый TextEdit (pid 52331) жив через 20 s без единой отправки
```

### Расхождения с SDK

```text
AEDataModel.h:431   kAEDefaultTimeout = -1
AEDataModel.h:432   kNoTimeOut        = -2
                    kAENormalTimeout  — НЕ СУЩЕСТВУЕТ (findings §4, DEC-002 называют его)

AppleEvents.h:615   kAEDoNotPromptForUserConsent = 0x00020000
                    "If set, and the AppleEvent requires user consent, do not prompt and
                     instead return errAEEventWouldRequireUserConsent"
                    -> без гранта ожидается -1744, а не -1743; DEC-002 трактует -1743
                       как немедленно терминальное
```

### Текст диалога согласия — дословно

Снят отдельным трайлом в конце сессии (сброс проверен на -1744 непосредственно перед):

```text
[значок приложения]

"Probe" wants access to control "TextEdit". Allowing control will provide access to
documents and data in "TextEdit", and to perform actions within that app.

The TASK-001 probe measures Apple Events consent behaviour against TextEdit.

[ Don't Allow ]   [ Allow ]
```

Две находки из самого диалога:

- имя приложения — **"Probe"**, то есть имя бандла `Probe.app`, а НЕ `CFBundleName`
  (`Terminator TASK-001 Probe`);
- вторая строка — `NSAppleEventsUsageDescription` дословно; это пользовательский текст.

Нажатые кнопки по трайлам: Allow (сертификатная ветка), Allow (ad-hoc контроль),
Don't Allow (трайл Deny), Allow (финальный трайл текста диалога). В листе несохранённых
изменений TextEdit — Delete.

### Предохранители пробника — проверены, а не только написаны

```text
субъект отсутствует, quit-путь:
  REFUSED: com.apple.TextEdit is not running — nothing was addressed
  nothing was sent — nothing to observe
субъект отсутствует, permission-путь:
  REFUSED: com.apple.TextEdit is not running — nothing was addressed
deadpid против ЖИВОГО pid (31245):
  REFUSED: pid 31245 is alive. This command only ever addresses a pid proven dead
```

Пробник за всю сессию адресовал только `com.apple.TextEdit`. Ни `forceTerminate`, ни
`terminate()`, ни сигналов — исходник чист по `check-forbidden.sh`.

### Блокировка pre-warming не ограничена

```text
блокировки вызова по пяти трайлам: 4.015 s, 5.431 s, 7.212 s, 147.968 s, 4049.816 s
последняя — 67 минут, диалог висел, пока оператор его переписывал
```

### Уборка — выполнена, и дала ещё одно измерение

Строка `claude → TextEdit` создана на первом (снятом) раунде. Пользователь выключил её
переключателем в System Settings 2026-08-27. Проверка **прямым exec** — он атрибутируется на
терминал, поэтому читает именно грант `claude`:

```text
до выключения:    check quit = 0 noErr
после выключения: check quit = -1743 errAEEventNotPermitted    <- НЕ -1744
```

**Переключатель в System Settings — не сброс.** Он оставляет строку и переводит её в
«отказано». В состояние «никогда не спрашивали» (`-1744`) возвращает только
`tccutil reset AppleEvents <bundle-id>`. Записано в findings §5 и внесено в TASK-009: там
требуется стартовое состояние `-1744`, и попытка добыть его через UI обречена.

Строка самого пробника снята, состояние проверено:

```text
$ tccutil reset AppleEvents com.svvoff.terminator.probe
Successfully reset AppleEvents approval status for com.svvoff.terminator.probe
$ run-probe.sh check quit
  status: -1744 (errAEEventWouldRequireUserConsent)
```

TextEdit закрыт вежливым событием: `AESendMessage: 0 (noErr)`, pid исчез через 0.257 s.
Незакрытых артефактов не осталось.
