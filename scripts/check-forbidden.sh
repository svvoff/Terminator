#!/usr/bin/env bash
# check-forbidden.sh — механические грep-гейты проекта Terminator.
#
# Кодирует один раз запреты, которые карточки задач требуют проверять грепом
# (см. TASK-004 → Validation requirements) и docs/ai/EXECUTOR.md → «Запрещено
# в коде этого проекта». Список живёт здесь, а не переписывается в каждой
# карточке, чтобы копии не разошлись.
#
# Проверяется только код: *.swift, *.sh, Package.swift. docs/ и .git/ не
# сканируются — там эти строки встречаются законно, как предмет обсуждения.
#
# Не выражается грепом и потому проверяется в ревью вручную
# (docs/ai/review-checklist.md):
#   - SuspendingClock в ПУТИ ДЕДЛАЙНА (сам по себе он разрешён: TASK-007
#     добавляет suspending-чтение для накопления фокуса);
#   - Date() внутри разрешения времени запуска процесса;
#   - privacy: .public на каждой интерполяции в лог-строке.
#
# Usage: scripts/check-forbidden.sh [REPO_ROOT]
# Exit code: 0 если нарушений нет (в т.ч. пока кода ещё не существует), 1 иначе.

set -uo pipefail

root="${1:-.}"
hits=0

# Файлы кода. Пока дерева исходников нет, список пуст и скрипт молча проходит.
# Сам этот скрипт исключён: он содержит все запрещённые строки как литералы.
# build.sh и остальные *.sh сканируются — 'swift run' пробирается именно туда.
code_files() {
  find "$root" \
    \( -path '*/.git' -o -path '*/docs' -o -path '*/.build' -o -path '*/build' \) -prune -o \
    -name 'check-forbidden.sh' -prune -o \
    \( -name '*.swift' -o -name '*.sh' \) -type f -print 2>/dev/null
}

# core_files — только чистое ядро: Foundation и никакого AppKit.
core_files() {
  find "$root/Sources/TerminatorCore" -name '*.swift' -type f -print 2>/dev/null
}

# check <lister> <fixed-string> <почему>
# Файлы читаются построчно, чтобы имена с пробелами не разъезжались, и grep не
# запускается вовсе, когда список пуст (иначе он ушёл бы читать stdin).
check() {
  local lister="$1" pattern="$2" why="$3" f out found=""
  while IFS= read -r f; do
    out="$(grep -Hn -F -- "$pattern" "$f" 2>/dev/null)" || true
    [ -n "$out" ] && found="${found}${out}
"
  done < <($lister)
  if [ -n "$found" ]; then
    printf 'FORBIDDEN: %s — %s\n' "$pattern" "$why"
    printf '%s' "$found" | sed 's/^/    /'
    hits=$((hits + 1))
  fi
}

# --- Завершение процессов (findings §4, §10; DEC-002) ------------------------
check code_files 'forceTerminate'   'DEC-002: только вежливый Apple Event'
check code_files '.terminate()'     'findings §4: terminate() эскалирует до SIGKILL'
check code_files 'SIGKILL'          'DEC-002: сигналы запрещены'
check code_files 'SIGTERM'          'DEC-002: сигналы запрещены'
check code_files 'kill('            'DEC-002: сигналы запрещены'
check code_files '==='              'findings §10: равенство NSRunningApplication ASN-based'

# --- Swift 6: эскейп-хетчи (findings §13) ------------------------------------
check code_files '@unchecked Sendable'   'findings §13: чинить форму, а не глушить диагностику'
check code_files '@preconcurrency'       'findings §13: то же'
check code_files 'swiftLanguageMode(.v5)' 'findings §13: весь пакет в Swift 6 language mode'

# --- Платформенные ловушки (findings §7, §11) --------------------------------
check code_files 'UserDefaults'  'findings §11: suiteName не привязывается к своему bundle id'
check code_files 'Bundle.module' 'findings §7: resources на исполняемом таргете не используются'
check code_files 'swift run'     'findings §7: даёт .prohibited-процесс без меню-бара'
check code_files 'beginActivity' 'не-цель: App Nap opt-out'

# --- Чистота ядра (findings §9, §13) -----------------------------------------
check core_files 'import AppKit'   'findings §13: TerminatorCore — только Foundation'
check core_files 'ContinuousClock' 'findings §9: дедлайн живёт на шкале Date'
check core_files 'DispatchTime'    'findings §9: то же'
check core_files 'protocol Clock'  'findings §13: редьюсер синхронный, протокола Clock нет'

if [ "$hits" -eq 0 ]; then
  echo "OK:    запрещённых конструкций не найдено"
  exit 0
fi
echo "Summary: $hits нарушение(й)."
exit 1
