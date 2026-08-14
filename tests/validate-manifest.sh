#!/usr/bin/env bash
# Manifest checks that do not need Omarchy installed.
#
# Mirrors what omarchy-plugin-validate enforces (so CI refuses anything the
# shell would reject), and adds two the stock validator has no opinion about:
# every declared setting must have a default, and that default must match the
# type the setting claims. Those are the ones easy to get wrong when adding a
# knob — the widget silently falls back and the setting looks broken.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
M="$ROOT/manifest.json"
FAIL=0

fail() { printf '  FAIL — %s\n' "$*"; FAIL=$((FAIL+1)); }
ok()   { printf '  ok   — %s\n' "$*"; }

command -v jq >/dev/null || { echo "jq is required"; exit 1; }
[ -f "$M" ] || { echo "no manifest.json at $M"; exit 1; }

if jq -e . "$M" >/dev/null 2>&1; then
  ok "manifest is valid JSON"
else
  fail "manifest is not valid JSON"
  exit 1
fi

if jq -e '.schemaVersion == 1' "$M" >/dev/null 2>&1; then
  ok "schemaVersion is 1"
else
  fail "schemaVersion must be the number 1"
fi

for field in id name version kinds entryPoints; do
  jq -e --arg f "$field" 'has($f)' "$M" >/dev/null 2>&1 \
    || fail "missing required field '$field'"
done
ok "required fields present"

ID=$(jq -r '.id // ""' "$M")
[[ $ID =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "invalid plugin id '$ID'"
[[ $ID != omarchy.* ]] || fail "id '$ID' uses the reserved omarchy.* namespace"
[[ $ID != *".."* ]] || fail "id '$ID' contains '..'"
ok "id '$ID' is well formed"

if jq -e '(.kinds | type) == "array" and (.kinds | length) > 0' "$M" >/dev/null 2>&1; then
  ok "kinds is a non-empty array"
else
  fail "kinds must be a non-empty array"
fi

# Entry points must be safe relative paths that actually exist.
while IFS=$'\t' read -r kind path; do
  [ -n "$path" ] || continue
  case "$path" in
    /*|*..*) fail "entry point '$kind' has an unsafe path: $path"; continue ;;
  esac
  if [ ! -f "$ROOT/$path" ]; then
    fail "entry point '$kind' points at a missing file: $path"
  elif [ -L "$ROOT/$path" ]; then
    fail "entry point '$kind' is a symlink: $path"
  fi
done < <(jq -r '.entryPoints // {} | to_entries[] | "\(.key)\t\(.value)"' "$M")
ok "entry points resolve to real files"

# Every kind that needs code has an entry point.
while read -r kind; do
  [ -n "$kind" ] || continue
  case "$kind" in
    service)    jq -e '.entryPoints.service'   "$M" >/dev/null || fail "kind 'service' needs entryPoints.service" ;;
    bar-widget) jq -e '.entryPoints.barWidget' "$M" >/dev/null || fail "kind 'bar-widget' needs entryPoints.barWidget" ;;
  esac
done < <(jq -r '.kinds[]' "$M")
ok "each kind has the entry point it needs"

# Project-specific: settings must be complete and self-consistent.
missing=$(jq -r '
  (.barWidget.defaults // {}) as $d
  | [ (.barWidget.schema // [])[]
      | select((.key | in($d)) | not)
      | .key ] | join(", ")' "$M")
if [ -z "$missing" ]; then
  ok "every declared setting has a default"
else
  fail "settings declared with no default: $missing"
fi

mismatch=$(jq -r '
  (.barWidget.defaults // {}) as $d
  | [ (.barWidget.schema // [])[]
      | select(.key | in($d))
      | . as $s
      | ($d[$s.key] | type) as $actual
      | select(
          ($s.type == "integer" and $actual != "number")
          or ($s.type == "boolean" and $actual != "boolean")
          or ($s.type == "string"  and $actual != "string"))
      | "\($s.key) declares \($s.type) but defaults to \($actual)" ] | join("; ")' "$M")
if [ -z "$mismatch" ]; then
  ok "defaults match their declared types"
else
  fail "$mismatch"
fi

# A schema default and the defaults block disagreeing is a silent trap.
drift=$(jq -r '
  (.barWidget.defaults // {}) as $d
  | [ (.barWidget.schema // [])[]
      | select(has("defaultValue") and (.key | in($d)))
      | select(.defaultValue != $d[.key])
      | "\(.key): schema says \(.defaultValue), defaults says \($d[.key])" ] | join("; ")' "$M")
if [ -z "$drift" ]; then
  ok "schema defaultValue agrees with the defaults block"
else
  fail "$drift"
fi

# The widget clamps every numeric setting itself, because `omarchy bar set`
# writes shell.json directly and never consults the schema. If a clamp and the
# schema disagree, the settings UI and the CLI quietly enforce different
# limits — which is exactly the kind of drift nobody notices by reading.
WIDGET="$ROOT/BarWidget.qml"
if [ -f "$WIDGET" ]; then
  clampfail=0
  while IFS=$'\t' read -r key min max; do
    line=$(grep -F "setting(\"$key\"" "$WIDGET" | head -1)
    if [ -z "$line" ]; then
      fail "setting '$key' is declared but the widget never reads it"
      clampfail=1
      continue
    fi
    if [ "$min" != "null" ] && ! grep -qF "Math.max($min," <<<"$line"; then
      fail "setting '$key' declares min $min but the widget does not clamp to it"
      clampfail=1
    fi
    if [ "$max" != "null" ] && ! grep -qF "Math.min($max," <<<"$line"; then
      fail "setting '$key' declares max $max but the widget does not clamp to it"
      clampfail=1
    fi
  done < <(jq -r '(.barWidget.schema // [])[]
    | select(.type == "integer")
    | "\(.key)\t\(.min // "null")\t\(.max // "null")"' "$M")
  [ "$clampfail" -eq 0 ] && ok "widget clamps agree with the declared min/max"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "manifest: all checks passed"
else
  echo "manifest: $FAIL check(s) failed"
fi
[ "$FAIL" -eq 0 ]
