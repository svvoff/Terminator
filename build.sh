#!/usr/bin/env bash
#
# build.sh — собирает и подписывает build/Terminator.app (TASK-002, DEC-007).
#
# Дев-луп:
#
#     ./build.sh && ./build/Terminator.app/Contents/MacOS/Terminator
#
# `swift run` НИКОГДА не покажет пункт в меню-баре. Голый исполняемый файл получает
# activation policy .prohibited ещё до первой строки кода, а Bundle.main.bundleIdentifier
# у него nil (findings §7). Отсутствие пункта меню-бара под `swift run` — не баг, и
# отлаживать там нечего: нужен именно бандл.
#
# Всё, что трогает TCC, Apple Events и диалоги согласия, запускается через
# `open build/Terminator.app`, а не прямым exec из Contents/MacOS: при прямом exec
# ответственным процессом становится терминал, и согласие записывается на него, а не на
# Terminator (findings §5, §7). Для TASK-002 это не нужно — строка адресована следующим
# карточкам. Прямой exec остаётся правильным везде, где нужен stdout.
#
# Порядок шагов не случаен. codesign запечатывает Contents/Resources: дописанный байт в
# запечатанный ресурс даёт «a sealed resource is missing or invalid» (findings §6).
# Поэтому подпись — ПОСЛЕДНЯЯ мутация бандла, после неё в Contents/ не пишется ничего,
# а `codesign --verify --strict` — терминальная команда скрипта.
#
# Usage: ./build.sh [debug|release] [--adhoc-control] [--self-test-guard]

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

CONFIG="debug"
ADHOC_CONTROL=0
SELF_TEST_GUARD=0

for arg in "$@"; do
  case "$arg" in
    debug|release)
      CONFIG="$arg"
      ;;
    --adhoc-control)
      ADHOC_CONTROL=1
      ;;
    --self-test-guard)
      SELF_TEST_GUARD=1
      ;;
    *)
      echo "build.sh: unknown argument: $arg" >&2
      echo "usage: ./build.sh [debug|release] [--adhoc-control] [--self-test-guard]" >&2
      exit 2
      ;;
  esac
done

IDENTITY="Terminator Dev"
APP="build/Terminator.app"
PLIST_TEMPLATE="Packaging/Info.plist"

# Две константы ниже — УТВЕРЖДЕНИЕ о подписанном бандле, а не второе определение его.
# CFBundleIdentifier продолжает жить в Packaging/Info.plist, сертификат — в keychain.
# Гейт существует ровно затем, чтобы заметить, когда эти два источника разойдутся с тем,
# что записала карточка TASK-002. Расхождение чинится там, где живёт настоящий источник,
# а не правкой этих строк «чтобы прошло».
EXPECTED_BUNDLE_ID="com.svvoff.terminator"
# SHA-1 сертификата подписи, нижним регистром — ровно так его печатает `codesign -d -r-`.
EXPECTED_CERT_SHA1="74d582911cd0b2c7ff3961af4bb0561efd6a8f24"
EXPECTED_REQUIREMENT="identifier \"$EXPECTED_BUNDLE_ID\" and certificate leaf = H\"$EXPECTED_CERT_SHA1\""

# Предикат гейта. Аргумент — уже очищенный от префикса текст designated requirement.
#
# Сравнение — ТОЧНОЕ равенство, а не «содержит», и это сознательно строго: любой
# косметический сдвиг формата вывода codesign обязан остановить сборку громко, а не тихо
# ослабить проверку. Форма позитивная и fail-closed — одно сравнение отвергает сразу
# четыре сценария, каждый из которых гейт раунда 1 пропускал молча:
#   ad-hoc подпись (DR = `cdhash H"..."`), чужой сертификат (другой хеш листа),
#   уехавший CFBundleIdentifier, сдвиг формата вывода `codesign -d -r-`.
requirement_is_expected() {
  [[ "$1" == "$EXPECTED_REQUIREMENT" ]]
}

# --- self-test гейта: ни сборки, ни подписи -------------------------------------------
# Флаг существует затем, чтобы доказать, что гейт отвергает ЧУЖОЙ сертификат, НЕ ПОДПИСЫВАЯ
# чужим сертификатом. `Apple Development: Vladimir Voytsekhovskiy (63PZ483Z52)` не
# используется, не экспортируется, не изменяется и не удаляется ни при каких
# обстоятельствах (DEC-007). Предикат — чистая функция от строки, поэтому его вердикты
# проверяются на синтетических строках, без единого лишнего вызова codesign.
self_test_case() {
  want="$1"
  name="$2"
  input="$3"
  if requirement_is_expected "$input"; then
    got="accept"
  else
    got="reject"
  fi
  if [[ "$got" == "$want" ]]; then
    echo "  OK   $name -> $got"
    return 0
  fi
  echo "  FAIL $name -> $got, ожидалось $want" >&2
  echo "       вход: $input" >&2
  return 1
}

if [[ $SELF_TEST_GUARD -eq 1 ]]; then
  echo "--- self-test гейта (ничего не собирается и не подписывается) ---"
  echo "ожидаемый designated requirement: $EXPECTED_REQUIREMENT"
  SELF_TEST_FAILURES=0
  # Хеши и идентификатор в отвергаемых случаях синтетические: это НЕ отпечаток какого-либо
  # реального сертификата на этой машине.
  self_test_case reject "ad-hoc подпись (cdhash)" \
    'cdhash H"10e8914b2d6adbdf7101a705d1af283b51ed471f"' \
    || SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
  self_test_case reject "чужой сертификат (другой хеш листа)" \
    "identifier \"$EXPECTED_BUNDLE_ID\" and certificate leaf = H\"00000000000000000000000000000000deadbeef\"" \
    || SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
  self_test_case reject "уехавший CFBundleIdentifier" \
    "identifier \"com.svvoff.terminatorr\" and certificate leaf = H\"$EXPECTED_CERT_SHA1\"" \
    || SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
  self_test_case accept "ожидаемый текст дословно" \
    "$EXPECTED_REQUIREMENT" \
    || SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
  if [[ $SELF_TEST_FAILURES -ne 0 ]]; then
    echo "build.sh: GUARD_SELF_TEST_FAILED: неверных вердиктов — $SELF_TEST_FAILURES из 4." >&2
    echo "  Предикат гейта не делает того, что о нём написано. Собирать нельзя." >&2
    exit 1
  fi
  echo "self-test: 4 из 4 вердиктов верны"
  exit 0
fi

# --- 1. компиляция ------------------------------------------------------------------
echo "--- swift build -c $CONFIG ---"
swift build -c "$CONFIG"

# Путь к бинарю спрашивается у SwiftPM, а не хардкодится: он зависит от тройки и от
# конфигурации.
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

# --- 2. сборка бандла ---------------------------------------------------------------
# rm -rf ДО сборки: ни один устаревший файл не должен пережить в подписанный бандл.
echo "--- assemble $APP ---"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

# Имя продукта = CFBundleExecutable, поэтому бинарь ложится под своим именем.
cp "$BIN_DIR/Terminator" "$APP/Contents/MacOS/Terminator"

# Info.plist — рукописный шаблон, лежит вне Sources/: под Sources/ SwiftPM счёл бы его
# ресурсом таргета (findings §7).
cp "$PLIST_TEMPLATE" "$APP/Contents/Info.plist"

# --- 3. подпись: последняя мутация бандла -------------------------------------------
# Без --options runtime (потребовал бы entitlement com.apple.security.automation.apple-events)
# и без файла entitlements. App Sandbox не включается никогда (findings §6, DEC-007).
#
# Ветки «если Terminator Dev не найден — подписать иначе» здесь нет и не появится:
# отсутствие identity обязано уронить сборку громко.
if [[ $ADHOC_CONTROL -eq 1 ]]; then
  # КОНТРОЛЬНЫЙ ОПЫТ, и это единственное место во всём проекте, где ad-hoc допустим.
  # Флаг существует ровно затем, чтобы показать: cdhash-гейт ниже действительно валит
  # сборку, а не просто написан. Этот путь НИКОГДА не производит проверенный бандл и
  # НЕ является запасным путём на случай неудачной подписи — ad-hoc DR меняется от
  # односимвольной правки исходника и дисквалифицирован findings §6.
  echo "--- codesign --force --sign - (AD-HOC CONTROL: сборка обязана упасть на гейте) ---"
  codesign --force --sign - "$APP"
else
  echo "--- codesign --force --sign \"$IDENTITY\" (последняя мутация бандла) ---"
  codesign --force --sign "$IDENTITY" "$APP"
fi

# --- 4. гейт designated requirement --------------------------------------------------
# Стоит ДО верификации, потому что ad-hoc-бандл верификацию проходит: одной верификации
# для этого мало. DR ad-hoc-подписи — `cdhash H"..."` без TeamIdentifier, и он меняется
# при любой правке исходника; DR подписи сертификатом переживает пересборку побайтово.
#
# Проверка позитивная: DR обязан быть ТОЧНО ожидаемым текстом. Прежняя форма называла одну
# плохую форму (`cdhash*`) и пропускала всё остальное — она молчала бы о подписи чужим
# сертификатом, об уехавшем CFBundleIdentifier (к нему TCC привязывает Automation-гранты,
# findings §6) и о следующем сдвиге формата вывода codesign. Случай ad-hoc отсюда никуда не
# делся: в `cdhash H"..."` ожидаемого текста нет.
echo "--- designated requirement guard ---"
DESIGNATED_REQUIREMENT="$(codesign -d -r- "$APP" 2>/dev/null)"
# Префикс снимается по «designated => », а не по началу строки: codesign печатает
# сертификатный DR как `designated => identifier ...`, а ad-hoc — как
# `# designated => cdhash H"..."`, с ведущим маркером комментария. Измерено на
# macOS 26.6.2 прогоном ./build.sh --adhoc-control; strip по началу строки пропускал
# ровно тот случай, ради которого гейт написан.
DESIGNATED_REQUIREMENT="${DESIGNATED_REQUIREMENT##*designated => }"
echo "designated requirement: $DESIGNATED_REQUIREMENT"

if ! requirement_is_expected "$DESIGNATED_REQUIREMENT"; then
  echo "build.sh: DESIGNATED_REQUIREMENT_MISMATCH: designated requirement бандла не равен" >&2
  echo "  ожидаемому. Сборка остановлена ДО верификации; бандл в $APP не годен." >&2
  echo "  ожидалось: $EXPECTED_REQUIREMENT" >&2
  echo "  получено:  $DESIGNATED_REQUIREMENT" >&2
  echo "  Четыре известные причины:" >&2
  echo "   1. ad-hoc подпись (codesign -s -): DR имеет вид cdhash H\"...\" и меняется от" >&2
  echo "      односимвольной правки исходника — дисквалифицировано findings §6, DEC-007." >&2
  echo "   2. бандл подписан ЧУЖИМ сертификатом: в DR другой хеш листа. Подписывать только" >&2
  echo "      identity \"$IDENTITY\", запасного пути нет; сертификат Apple Development" >&2
  echo "      (63PZ483Z52) запрещён к использованию в этом проекте (DEC-007)." >&2
  echo "   3. уехал CFBundleIdentifier в $PLIST_TEMPLATE: TCC привязывает Automation-гранты" >&2
  echo "      к bundle id (findings §6), поэтому тихая смена идентификатора стоит грантов." >&2
  echo "   4. сдвинулся формат вывода codesign -d -r-: сравнение здесь точное, и это" >&2
  echo "      сознательно — косметический сдвиг обязан остановить сборку громко." >&2
  echo "  Проверить сам предикат, ничего не собирая: ./build.sh --self-test-guard" >&2
  exit 1
fi

# --- 5. верификация: терминальный шаг ------------------------------------------------
# exec — чтобы после подписи в бандл структурно нечему было писать, и чтобы код возврата
# скрипта был буквально кодом возврата этой команды.
echo "--- codesign --verify --strict (терминальный шаг) ---"
exec codesign --verify --strict "$APP"
