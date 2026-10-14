#!/bin/sh
# shellcheck disable=SC2034,SC2154
set -e
SRC="${1:-$(dirname "$0")/../feats/compat_run.sh}"
[ -f "$SRC" ] || { echo "envcheck: $SRC not present, skipped"; exit 0; }

strip() { sed 's/^[[:space:]]*//'; }
dllpath_line=$(grep 'export WINEDLLPATH=' "$SRC" | grep 'x86_64-windows' | strip)
overrides_line=$(grep 'export WINEDLLOVERRIDES=' "$SRC" | grep 'lsteamclient=b' | strip)
[ -n "$dllpath_line" ] || { echo "FAIL: WINEDLLPATH merge not found"; exit 1; }
[ -n "$overrides_line" ] || { echo "FAIL: WINEDLLOVERRIDES merge not found"; exit 1; }

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n         want [%s]\n         got  [%s]\n' "$1" "$2" "$3"; fails=$((fails + 1)); }
is() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }

echo "== WINEDLLPATH (first match wins, runner first) =="
CX_ROOT=/R
wine_unix=/R/lib/wine/x86_64-unix
WINEDLLPATH=""
eval "$dllpath_line"
is "no user value" "/R/lib/wine/x86_64-windows:/R/lib/wine/x86_64-unix" "$WINEDLLPATH"
WINEDLLPATH="/user/dir"
eval "$dllpath_line"
is "user value last" "/R/lib/wine/x86_64-windows:/R/lib/wine/x86_64-unix:/user/dir" "$WINEDLLPATH"

echo "== WINEDLLOVERRIDES (last wins, trio last) =="
WINEDLLOVERRIDES=""
eval "$overrides_line"
is "no user value" "steamclient=n;steamclient64=n;lsteamclient=b" "$WINEDLLOVERRIDES"
WINEDLLOVERRIDES="winhttp=n,b"
eval "$overrides_line"
is "user value first" "winhttp=n,b;steamclient=n;steamclient64=n;lsteamclient=b" "$WINEDLLOVERRIDES"
WINEDLLOVERRIDES="lsteamclient=n"
eval "$overrides_line"
is "trio outranks user" "lsteamclient=n;steamclient=n;steamclient64=n;lsteamclient=b" "$WINEDLLOVERRIDES"

echo "== Apple GPTK initialization and launcher environment =="
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
np_support="$work/Application Support/notproton"
np_build="test"
library="$np_support/runners/crossover-$np_build/CrossOver/lib64/apple_gptk/external/libd3dshared.dylib"
init=$(sed -n '/^CX_ROOT=/,/^wine_unix=/p' "$SRC")
# shellcheck disable=SC2016 # Match the literal launcher loop.
forward=$(sed -n '/^for name in $(/,/^done$/p' "$SRC")
[ -n "$init" ] && [ -n "$forward" ] || { echo "FAIL: runner environment blocks not found"; exit 1; }
unset CX_APPLEGPTK_LIBD3DSHARED_PATH
eval "$init"
is "runner without the library leaves the path unset" "" "${CX_APPLEGPTK_LIBD3DSHARED_PATH:-}"
mkdir -p "$(dirname "$library")"
: > "$library"
eval "$init"
is "bundled library is selected" "$library" "${CX_APPLEGPTK_LIBD3DSHARED_PATH:-}"
is "helpers inherit the library path" "$library" "$(sh -c 'printf %s "$CX_APPLEGPTK_LIBD3DSHARED_PATH"')"
set --
eval "$forward"
forwarded=""
for arg in "$@"; do
  case "$arg" in CX_APPLEGPTK_LIBD3DSHARED_PATH=*) forwarded=${arg#*=} ;; esac
done
is "game launcher receives the path as one argument" "$library" "$forwarded"
# macOS sed stops at the first invalid UTF-8 value.
# shellcheck disable=SC2016 # The stub and loop expand inside the child shell.
after_bad=$(env -i PATH="$PATH" LANG=en_US.UTF-8 DXVK_HUD=1 sh -c '
  env() { printf "A_BAD=a\377b\nDXVK_HUD=1\n"; }
  f=$1; set --; eval "$f"; printf "%s " "$@"' sh "$forward")
is "settings after a non-UTF-8 value are forwarded" "--env DXVK_HUD=1 " "$after_bad"

echo "== custom per-game variables survive the launcher boundary =="
compatdata="$work/compatdata/287700"
mkdir -p "$compatdata"
export STEAM_COMPAT_DATA_PATH="$compatdata"
rm -f "$compatdata/notproton-environment"
export NOTPROTON_FORWARD_ENV="D3DMETAL_FRAMEWORK_PATH,FSR4_HOOK_LOG,FSR4_ROOT,FSR4_REPLACE,FSR4_PANEL,FSR4_VERSION,FSR4_PROFILE"
export D3DMETAL_FRAMEWORK_PATH=/tmp/D3DMetal.framework/Versions/A/D3DMetal
export FSR4_HOOK_LOG=/tmp/hook.log
export FSR4_ROOT="/tmp/fsr4 root"
export FSR4_REPLACE=1 FSR4_PANEL=1 FSR4_VERSION=4.1.1 FSR4_PROFILE=lossy
set --
eval "$forward"
forwarded_value() {
  key="$1"
  shift
  for arg in "$@"; do
    case "$arg" in
      "$key"=*) printf '%s' "$arg" | sed 's/^[^=]*=//'; return ;;
    esac
  done
}
is "D3DMETAL_FRAMEWORK_PATH survives" "$D3DMETAL_FRAMEWORK_PATH" "$(forwarded_value D3DMETAL_FRAMEWORK_PATH "$@")"
is "FSR4_HOOK_LOG survives" "$FSR4_HOOK_LOG" "$(forwarded_value FSR4_HOOK_LOG "$@")"
is "FSR4_ROOT with spaces survives as one value" "$FSR4_ROOT" "$(forwarded_value FSR4_ROOT "$@")"
is "FSR4_REPLACE survives" "$FSR4_REPLACE" "$(forwarded_value FSR4_REPLACE "$@")"
is "FSR4_PANEL survives" "$FSR4_PANEL" "$(forwarded_value FSR4_PANEL "$@")"
is "FSR4_VERSION survives" "$FSR4_VERSION" "$(forwarded_value FSR4_VERSION "$@")"
is "FSR4_PROFILE survives" "$FSR4_PROFILE" "$(forwarded_value FSR4_PROFILE "$@")"
is "internal forward marker is not exposed to the game" "" "$(forwarded_value NOTPROTON_FORWARD_ENV "$@")"

echo "== Rosetta-only settings on arm64 Wine =="
drop=$(sed -n '/^np_dropped=""$/,/^fi$/p' "$SRC")
[ -n "$drop" ] || { echo "FAIL: the arm64 settings block was not found"; exit 1; }
drop_at=$(grep -n '^np_dropped=""$' "$SRC" | cut -d: -f1)
# shellcheck disable=SC2016 # Match the literal launcher loop.
forward_at=$(grep -n '^for name in $(' "$SRC" | cut -d: -f1)
[ "$drop_at" -lt "$forward_at" ] ||
  bad "the arm64 settings block runs before the forwarding loop" "< $forward_at" "$drop_at"
seen() { sh -c 'env | sed -nE "s/^(CX_GRAPHICS_BACKEND|D3DM_[A-Z0-9_]*|DXMT_[A-Z0-9_]*|ROSETTA_[A-Z0-9_]*)=.*/\1/p" | sort | tr "\n" " "'; }
for name in $(seen); do unset -v "$name"; done
CX_ROOT="/R R"
set_all() { export CX_GRAPHICS_BACKEND=d3dmetal D3DM_ENABLE_METALFX=1 ROSETTA_ADVERTISE_AVX=0 DXMT_CONFIG=x; }
set_all
wine_unix="/R R/lib/wine/x86_64-unix"
eval "$drop"
is "x86_64 Wine keeps every setting" \
  "CX_GRAPHICS_BACKEND D3DM_ENABLE_METALFX DXMT_CONFIG ROSETTA_ADVERTISE_AVX " "$(seen)"
is "x86_64 Wine logs nothing" "" "$np_dropped"
wine_unix="/R R/lib/wine/aarch64-unix"
eval "$drop"
is "D3DMetal and Rosetta settings leave the environment" "DXMT_CONFIG " "$(seen)"
is "the run log names what was ignored" \
  "CX_GRAPHICS_BACKEND=d3dmetal D3DM_ENABLE_METALFX ROSETTA_ADVERTISE_AVX" "$np_dropped"
set_all
export CX_GRAPHICS_BACKEND=dxmt
unset -v D3DM_ENABLE_METALFX ROSETTA_ADVERTISE_AVX
eval "$drop"
is "other backends stay" "CX_GRAPHICS_BACKEND DXMT_CONFIG " "$(seen)"
is "nothing to ignore logs nothing" "" "$np_dropped"
unset -v CX_GRAPHICS_BACKEND DXMT_CONFIG

if [ "$fails" -eq 0 ]; then
	echo "==> envcheck: all assertions hold"
else
	echo "==> envcheck: $fails failed"
	exit 1
fi
