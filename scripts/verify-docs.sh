#!/usr/bin/env bash
# verify-docs.sh — consistency check for token-aware product docs.
#
# Status model: the directory a card is in IS its status — the only copy.
# The backlog index is a static router and must hold no per-task data.
# This script checks what can still go wrong under that model:
#   1. the index contains per-task rows (forbidden — they drift);
#   2. a task id exists in more than one status directory (ambiguous status);
#   3. leftover 'status:' frontmatter (pre-migration remnant — remove it);
#   4. cards missing an 'id' in frontmatter;
#   5. depends_on / epic references that do not resolve (warnings).
#
# Usage:
#   scripts/verify-docs.sh [PRODUCT_DOCS_ROOT]
#
# PRODUCT_DOCS_ROOT defaults to ".". It must be a directory that contains
# docs/product/backlog/. Run it in the meta-repo against an example, or inside
# a configured target repo before the delivery loop selects a task.
#
# Exit code: 0 if no ERRORs, 1 otherwise. WARNs never fail the run.

set -euo pipefail

root="${1:-.}"
backlog="$root/docs/product/backlog"
index="$backlog/index.md"

errors=0
warns=0

err()  { printf 'ERROR: %s\n' "$1"; errors=$((errors + 1)); }
warn() { printf 'WARN:  %s\n' "$1"; warns=$((warns + 1)); }
ok()   { printf 'OK:    %s\n' "$1"; }

if [ ! -d "$backlog" ]; then
  err "no backlog directory at $backlog"
  echo "Summary: $errors error(s), $warns warning(s)."
  exit 1
fi

# Read a scalar frontmatter field (first match) from a markdown file.
# frontmatter is the block between the first two '---' lines.
fm() { # fm <file> <field>
  awk -v field="$2" '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---" { exit }
    infm {
      if ($0 ~ "^"field":") {
        sub("^"field":[[:space:]]*", "")
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        print
        exit
      }
    }
  ' "$1"
}

# Card files: every .md under tasks/, excluding README.md (routing docs, not cards).
list_cards() { # list_cards <dir>
  find "$1" -type f -name '*.md' ! -name 'README.md' 2>/dev/null
}

# --- Check 1: index is a static router — no per-task rows ---------------------
if [ -f "$index" ]; then
  if grep -Eq '^\|[[:space:]]*(TASK|EPIC)-' "$index"; then
    err "index.md contains per-task/epic table rows — the index is a static router; statuses live in directories only"
  fi
else
  err "no backlog index at $index"
fi

# --- Check 2,3,4: one id per status directory; no leftover status; id present -
all_ids=""
while IFS= read -r f; do
  id="$(fm "$f" id)"
  if [ -z "$id" ]; then
    err "$f: missing 'id' in frontmatter"
    continue
  fi
  if [ -n "$(fm "$f" status)" ]; then
    err "$f: leftover 'status' in frontmatter — status is the directory; remove the field"
  fi
  case " $all_ids " in
    *" $id "*) err "$id appears in more than one card file under tasks/ — status is ambiguous" ;;
    *) all_ids="$all_ids $id" ;;
  esac
done < <(list_cards "$backlog/tasks")

has_id() { case " $all_ids " in *" $1 "*) return 0;; *) return 1;; esac; }

# Same duplicate/leftover checks for epics.
epic_ids=""
if [ -d "$backlog/epics" ]; then
  while IFS= read -r f; do
    eid="$(fm "$f" id)"
    [ -z "$eid" ] && continue
    if [ -n "$(fm "$f" status)" ]; then
      err "$f: leftover 'status' in frontmatter — status is the directory; remove the field"
    fi
    case " $epic_ids " in
      *" $eid "*) err "$eid appears in more than one card file under epics/ — status is ambiguous" ;;
      *) epic_ids="$epic_ids $eid" ;;
    esac
  done < <(list_cards "$backlog/epics")
fi

# --- Check 5: depends_on / epic references resolve (warnings) -----------------
while IFS= read -r f; do
  deps="$(fm "$f" depends_on)"
  # inline list form: [TASK-002, TASK-003] or [] or 'none'
  deps="$(printf '%s' "$deps" | tr -d '[]' | tr ',' ' ')"
  for d in $deps; do
    case "$d" in
      TASK-*) has_id "$d" || warn "$f: depends_on '$d' does not resolve to a known task";;
    esac
  done
  epic="$(fm "$f" epic)"
  case "$epic" in
    EPIC-*)
      if ! find "$backlog/epics" -type f -name "*$epic*" 2>/dev/null | grep -q .; then
        warn "$f: epic '$epic' has no matching card under epics/"
      fi
      ;;
  esac
done < <(list_cards "$backlog/tasks")

# --- Summary ------------------------------------------------------------------
[ "$errors" -eq 0 ] && ok "backlog docs are consistent"
echo "Summary: $errors error(s), $warns warning(s)."
[ "$errors" -eq 0 ]
