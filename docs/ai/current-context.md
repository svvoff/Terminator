# Контекст текущей задачи

<!--
Переписывается оркестратором при каждом выборе задачи — до того, как написан пакет.
Две функции: видно, на что потрачен контекст, и файл переживает переезд на новую сессию
(migration-prompt ссылается на него).

Держи его коротким. Если он разрастается в пересказ карточки — он больше не выполняет ни одну
из двух функций.
-->

## Выбранная задача

**TASK-002** — SwiftPM package, .app build script, stable signing, menu bar skull.
Карточка: `docs/product/backlog/tasks/done/2026-08/TASK-002-package-and-app-bundle.md`.
**Принята 2026-08-27.** Следующая задача ещё не выбрана — этот файл перепишется при её выборе.

## Почему выбрана

P0, `risk: medium`, `depends_on: [TASK-001]` — единственная зависимость лежит в
`done/2026-08/`, стоп-условие спайка не сработало. В `ready/` восемь карточек; зависимости
выполнены только у TASK-002 и TASK-009, остальные шесть транзитивно ждут TASK-002.
**TASK-009** (P0, `risk: high`, зона 4 — закрывает чужие приложения) не выбрана: она требует
отдельного разрешения и гейтит только TASK-005, то есть TASK-002 не блокирует.
`scripts/verify-docs.sh` — зелёный (0 ошибок, 0 предупреждений) на момент выбора.

## Прочитано

- Tier 0: `current-state.md`, `backlog/index.md`, `execution-state.md`, `validation/index.md`.
- Tier 1: карточка TASK-002, `decisions/index.md`, **DEC-006**, **DEC-007**, **DEC-009**,
  `docs/ai/execution-policy.md`, `docs/ai/EXECUTOR.md`, `docs/ai/review-checklist.md`,
  `docs/ai/task-packet-template.md`, `docs/ai/execution-report-template.md`,
  `scripts/check-forbidden.sh`, `probes/task-001/build-probe.sh`,
  `docs/product/design/menu-bar-icon-{idle,active}.svg`.
- Findings по номерам: **§6** (подпись), **§7** (упаковка и activation policy), **§8** (иконка),
  **§13** (Swift 6 и форма ядра), **§14** (логи), плюс **§5** (только абзац про
  `NSAppleEventsUsageDescription`) и **§11** (только абзац про `NSSupportsSuddenTermination`).

§5 и §11 не названы в `context_refs`, но взяты точечно: карточка прямо ссылается на них в
разделах Info.plist и Non-goals, а без них два требования выглядят произвольными.

## Намеренно не прочитано

`tasks/done/`, `tasks/deferred/` (TASK-101…107), `epics/`, `decisions/archive/`, DEC-001…005 и
DEC-008, стадии роадмапа, `execution-log/archive/`, `project-brief.md`, `assumptions.md`,
`configurator-input.md`, findings §1–4, §9, §10, §12.

## Закреплено для пакета

- **DEC-006** — анти-обход не-цель: один процесс, никакого хелпера, никакого самоперезапуска.
- **DEC-007** — форма сборки и подпись; identity только `Terminator Dev`.
- **DEC-009** — иконка: концепт B, рисуется кодом, `isTemplate = false`; её Review trigger —
  первый рендер на живой машине **в этой задаче**.

Сверено по колонке «Applies to» в `decisions/index.md`. **Найдено расхождение:** роутер и
`applies_to` самой карточки DEC-006 называют TASK-002, а `context_refs` задачи его не
перечисляли. Решение пользователя 2026-08-27: добавить DEC-006 в `context_refs` карточки и в
пакет. Сделано; расхождений больше нет.

- Findings **§6**, **§7**, **§8**, **§13**, **§14** — плюс точечно §5 и §11, как выше.

## Маршрут исполнения

**Делегировано** `claude-code` через `.claude/skills/executor/`. По `execution-policy.md`:
радиус поражения — продакшн-код и скрипт сборки; цена проверки низкая (дифф плюс прогон
`build.sh`); свежий контекст исполнителя полезен, потому что вся эта сессия провела в голове
разбор эскалаций TASK-001, а карточке они не нужны.

Пакет: `docs/ai/handoff/current-task-packet.md`.
Отчёт: `docs/ai/handoff/current-execution-report.md`. Ревью — **отдельным ходом**.

## Гейты риска

Разрешение пользователя получено **2026-08-27** на зоны **1** (подпись и идентичность кода:
`codesign`, выбор identity, designated requirement, порядок шагов в `build.sh`) и **2**
(Keychain — использование существующего `Terminator Dev`).

Зоны 3 (TCC), 4 (завершение чужих процессов), 5 (LaunchAgents) и 6 (формат конфига) в этой
карточке не участвуют вовсе, и пакет это прямо запрещает. Сертификат
`Apple Development: Vladimir Voytsekhovskiy (63PZ483Z52)` не используется, не экспортируется,
не изменяется и не удаляется.

Ad-hoc подпись разрешена **только** как явно названный карточкой контрольный опыт для
демонстрации cdhash-гейта (флаг `--adhoc-control`), никогда как запасной путь при неудаче
подписи.

## Требования валидации

`validation_profile: [swift-build, manual-checklist]`.

L0 исполнитель закрывает сам: `swift build`, `swift build -c release` (без предупреждений),
`./build.sh` с терминальным `codesign --verify --strict`, транскрипт срабатывания cdhash-гейта,
две строки designated requirement до и после односимвольной правки, `check-forbidden.sh`.

L5 исполнитель **не засчитывает**: запуск бандла, видимость черепа в меню-баре, открытие
поповера, значения `activationPolicy` и `Bundle.main.bundleIdentifier`, сверка idle/active
глифа с эталонными SVG в светлой и тёмной теме (Review trigger DEC-009). Приложение исполнитель
не запускает вовсе.

## Состояние

**TASK-002 принята (ACCEPT) 2026-08-27.** Три раунда исполнения, каждый отревьюен отдельным
ходом; карточка в `tasks/done/2026-08/`, в `in-progress/` пусто.

Два амендмента дописаны в карточку по ходу, оба с разрешения пользователя:

1. cdhash-гейт переписан с блоклиста на fail-closed позитивную проверку designated requirement
   плюс `--self-test-guard`;
2. состояние глаз глифа поднято в `App` и переключается кнопкой — Review trigger DEC-009
   спрашивает про различимость на фоне **меню-бара**, а раунд 1 отвечал образцами в поповере.

Три измерения ушли в findings: **§6** — ad-hoc бандл проходит `codesign --verify --strict` с
нулём; ad-hoc DR печатается с ведущим `# `, сертификатный — без; верификация зависит от доступа
к keychain (`CSSMERR_TP_NOT_TRUSTED` в песочнице на исправном бандле). **§8** — лейбл
`MenuBarExtra` реактивен, прямая форма `Image(nsImage:)` без `.id(…)`.

Ручной чеклист выполнил автор: `.accessory` (rawValue 1) и `com.svvoff.terminator`, череп
читается в обеих темах, глиф в баре меняется по кнопке, Quit закрывает приложение. **Review
trigger DEC-009 закрыт**, геометрия остаётся.

Машина: macOS **26.6.2 (25G83)**, Swift 6.2.4, arm64.

Следующая задача — **TASK-003**. **TASK-005 не берётся до TASK-009.**
