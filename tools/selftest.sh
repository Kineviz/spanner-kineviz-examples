#!/usr/bin/env bash
#
# Offline self-test. Everything checkable without cloud credentials.
#
# The contract checker validates structure; this validates *behaviour* — that
# scripts fail correctly, that SQL templates fully substitute, that documented
# commands actually work, and that teardown cannot delete more than it created.
#
#   ./tools/selftest.sh          human output
#   ./tools/selftest.sh --quiet  only failures
#
# Creates nothing, needs no network, touches no cloud resource.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

pass=0 fail=0
_g=$'\033[32m'; _r=$'\033[31m'; _d=$'\033[2m'; _0=$'\033[0m'
[ -t 1 ] || { _g=""; _r=""; _d=""; _0=""; }

ok()   { pass=$((pass+1)); [ "$QUIET" = 1 ] || printf '  %s✓%s %s\n' "$_g" "$_0" "$1"; }
bad()  { fail=$((fail+1)); printf '  %s✗%s %s\n' "$_r" "$_0" "$1"; [ -n "${2:-}" ] && printf '      %s%s%s\n' "$_d" "$2" "$_0"; }
grp()  { [ "$QUIET" = 1 ] || printf '\n%s\n' "$1"; }

demos() { find demos -mindepth 1 -maxdepth 1 -type d -not -name '_*' | sort; }

# These tests overwrite each demo's .env with the placeholder example, so any
# real .env has to be preserved. An earlier version restored it inside the first
# test loop and then a later loop deleted it again — which silently destroyed
# working config. Back up once, restore on any exit.
BACKUP_DIR=$(mktemp -d)
save_envs() {
  for d in $(demos); do
    [ -f "$d/.env" ] && cp "$d/.env" "$BACKUP_DIR/$(basename "$d").env"
  done
  return 0
}
restore_envs() {
  for d in $(demos); do
    rm -f "$d/.env"
    [ -f "$BACKUP_DIR/$(basename "$d").env" ] && cp "$BACKUP_DIR/$(basename "$d").env" "$d/.env"
  done
  rm -rf "$BACKUP_DIR"
  return 0
}
trap restore_envs EXIT INT TERM
save_envs

# ---------------------------------------------------------------------------
grp "1. Scripts fail correctly when config is missing"
# A script that silently proceeds without config is worse than one that fails.

for d in $(demos); do
  slug=$(basename "$d")
  rm -f "$d/.env"

  out=$("$d/scripts/preflight.sh" 2>&1); rc=$?
  if [ $rc -eq 0 ]; then
    bad "$slug preflight: exits 0 with no .env" "it should refuse to run"
  elif ! printf '%s' "$out" | grep -q 'REMEDIATION:'; then
    bad "$slug preflight: no REMEDIATION line" "AGENTS.md tells agents to relay it"
  else
    ok "$slug preflight refuses without .env, with remediation"
  fi

  # Placeholder values must be rejected, not used.
  cp "$d/.env.example" "$d/.env"
  out=$("$d/scripts/preflight.sh" 2>&1); rc=$?
  if [ $rc -eq 0 ]; then
    bad "$slug preflight: accepts placeholder .env" "would run against 'your-project-id'"
  else
    ok "$slug preflight rejects placeholder values"
  fi
  rm -f "$d/.env"
done

# ---------------------------------------------------------------------------
grp "2. --json emits valid JSON"
# Agents parse this. One unescaped newline breaks the contract.

for d in $(demos); do
  slug=$(basename "$d")
  cp "$d/.env.example" "$d/.env"
  out=$("$d/scripts/preflight.sh" --json 2>&1)
  rm -f "$d/.env"
  if printf '%s\n' "$out" | python3 -c '
import json,sys
n=0
for line in sys.stdin:
    line=line.strip()
    if line:
        json.loads(line); n+=1
sys.exit(0 if n else 1)' 2>/dev/null; then
    ok "$slug --json output parses"
  else
    bad "$slug --json output is not valid JSON" "$(printf '%s' "$out" | head -2)"
  fi
done

# ---------------------------------------------------------------------------
grp "3. SQL templates fully substitute"
# A leftover \${VAR} reaches BigQuery as a literal and fails at runtime, after
# the person has already waited. Catch it here instead.

for d in $(demos); do
  slug=$(basename "$d")
  if [ ! -d "$d/sql" ] || ! compgen -G "$d/sql/*.sql" >/dev/null; then
    ok "$slug ships no SQL of its own (nothing to substitute)"
    continue
  fi
  # Every placeholder the demo's own setup.sh knows how to replace.
  known=$(grep -oE 's\|\\\$\{[A-Z_]+\}' "$d/scripts/setup.sh" 2>/dev/null \
          | grep -oE '\{[A-Z_]+\}' | tr -d '{}' | sort -u)
  for f in "$d"/sql/*.sql; do
    used=$(grep -oE '\$\{[A-Z_]+\}' "$f" | tr -d '${}' | sort -u)
    missing=""
    for v in $used; do
      printf '%s\n' "$known" | grep -qx "$v" || missing="$missing $v"
    done
    if [ -n "$missing" ]; then
      bad "$slug $(basename "$f"): placeholders never substituted:$missing" \
          "setup.sh's render() does not handle them"
    else
      ok "$slug $(basename "$f") placeholders all substituted"
    fi
  done
done

# ---------------------------------------------------------------------------
grp "4. Documented query commands actually work"
# queries/README.md tells people to run envsubst. If the .gql placeholders and
# the .env variable names disagree, that command silently produces empty
# identifiers — which is worse than an error.

for d in $(demos); do
  slug=$(basename "$d")
  [ -d "$d/queries" ] || continue
  ph=$(grep -rhoE '\$\{[A-Z_]+\}' "$d"/queries/*.gql 2>/dev/null | tr -d '${}' | sort -u)
  [ -z "$ph" ] && { ok "$slug queries use no placeholders"; continue; }
  missing=""
  for v in $ph; do
    grep -qE "^${v}=" "$d/.env.example" || missing="$missing $v"
  done
  if [ -n "$missing" ]; then
    bad "$slug queries reference \$$missing, absent from .env.example" \
        "the documented 'envsubst < query.gql' would substitute empty strings"
  else
    ok "$slug query placeholders all defined in .env.example"
  fi
done

# ---------------------------------------------------------------------------
grp "5. Every variable a script reads is in .env.example"

for d in $(demos); do
  slug=$(basename "$d")
  req=$(grep -rhoE 'require_env [A-Z_ ]+' "$d"/scripts/*.sh 2>/dev/null \
        | sed 's/require_env //' | tr ' ' '\n' | grep -E '^[A-Z_]+$' | sort -u)
  missing=""
  for v in $req; do
    grep -qE "^${v}=" "$d/.env.example" || missing="$missing $v"
  done
  if [ -n "$missing" ]; then
    bad "$slug: required but not in .env.example:$missing"
  else
    ok "$slug .env.example covers every require_env"
  fi
done

# ---------------------------------------------------------------------------
grp '5b. Every ${VAR} a script expands is in .env.example'
# Section 5 checks require_env, which is explicit. This catches the other case:
# a variable expanded directly in a script. Under `set -u` an unset one is
# FATAL, so a stale reference kills the step at runtime.
#
# Found by a real failure: supply-chain-deps was rewritten from "top N packages"
# to a seed list, and .env.example / setup.sh / preflight.sh were all updated —
# but handoff.sh still expanded ${TOP_N_PACKAGES}. The demo built its graph,
# verified it, then died printing the summary. Nothing tested handoff.sh.

for d in $(demos); do
  slug=$(basename "$d")
  # Variables the scripts EXPAND. A backslash-escaped \${NAME} is a literal
  # string handed to sed for SQL templating, not a shell expansion, so strip
  # those first — otherwise every SQL placeholder reads as an undefined variable.
  used=$(sed 's/\\\${[A-Z][A-Z0-9_]*}//g' "$d"/scripts/*.sh 2>/dev/null \
         | grep -ohE '\$\{[A-Z][A-Z0-9_]*(:-[^}]*)?\}' \
         | sed 's/[${}]//g; s/:-.*//' | sort -u)
  missing=""
  for v in $used; do
    case "$v" in
      GXR_*|BASH_SOURCE|PATH|HOME|PWD|SHELL|USER|EOF) continue ;;
    esac
    grep -qE "^${v}=" "$d/.env.example" 2>/dev/null && continue
    # Also fine if a script assigns it itself.
    grep -qE "^[[:space:]]*(local +)?${v}=" "$d"/scripts/*.sh 2>/dev/null && continue
    missing="$missing $v"
  done
  if [ -n "$missing" ]; then
    bad "$slug: script expands undefined var(s):$missing" \
        "under 'set -u' this aborts the step at runtime"
  else
    ok "$slug scripts expand only defined variables"
  fi
done

# ---------------------------------------------------------------------------
grp "6. Teardown deletes only what the demo created"
# The one irreversible action in the repo. A too-broad delete here destroys
# someone's data, so the bar is higher than "looks right".

for d in $(demos); do
  slug=$(basename "$d")
  t="$d/scripts/teardown.sh"
  [ -f "$t" ] || { bad "$slug: no teardown.sh"; continue; }

  # Deleting a whole bucket, or a dataset built from anything but the demo's
  # own configured name, is never correct.
  if grep -qE 'rm -r .*gs://\$\{?[A-Z_]+\}?/?"?$' "$t"; then
    bad "$slug teardown: deletes an entire bucket" "must be scoped to the demo's own prefix"
  elif grep -qE 'rm -rf? +/|rm -rf? +\$HOME|rm -rf? +~' "$t"; then
    bad "$slug teardown: unsafe local path deletion"
  else
    ok "$slug teardown scope looks safe"
  fi

  # Whatever demo.yaml declares as created must be removed.
  if grep -q 'bq://' "$d/demo.yaml" && ! grep -q 'rm .*--dataset' "$t"; then
    bad "$slug teardown: demo.yaml declares a BigQuery dataset but teardown does not remove one"
  fi
  if grep -q 'gs://' "$d/demo.yaml" && ! grep -q 'gsutil.*rm' "$t"; then
    bad "$slug teardown: demo.yaml declares GCS objects but teardown does not remove them"
  fi
  if grep -q 'spanner://' "$d/demo.yaml" && ! grep -q 'spanner databases delete' "$t"; then
    bad "$slug teardown: demo.yaml declares a Spanner database but teardown does not drop it"
  fi
  # A Spanner instance can hold other people's databases and is the thing that
  # bills. Deleting one to clean up a demo is never acceptable.
  if grep -q 'spanner instances delete' "$t"; then
    bad "$slug teardown: deletes a Spanner INSTANCE" "drop only the database this demo created"
  fi
done

# ---------------------------------------------------------------------------
grp "7. Setup is idempotent"
# Agents retry, and so do people. A second run must converge, not duplicate.

for d in $(demos); do
  slug=$(basename "$d")
  s="$d/scripts/setup.sh"
  bad_tbl=0
  for f in "$d"/sql/*.sql; do
    [ -f "$f" ] || continue
    # CREATE TABLE without OR REPLACE fails on a re-run.
    if grep -qiE '^\s*CREATE\s+TABLE\s' "$f"; then bad_tbl=1; fi
    if grep -qiE '^\s*CREATE\s+PROPERTY\s+GRAPH\s' "$f"; then bad_tbl=1; fi
  done
  if [ "$bad_tbl" = 1 ]; then
    bad "$slug: SQL uses CREATE without OR REPLACE" "a re-run after partial failure would error"
  else
    ok "$slug SQL is re-runnable (CREATE OR REPLACE)"
  fi
  # Dataset creation must tolerate an existing dataset.
  if grep -q 'mk --dataset' "$s" && ! grep -qE 'show --dataset|already exists|\|\| *(true|info)' "$s"; then
    bad "$slug setup: 'bq mk --dataset' not guarded" "second run would fail"
  fi
done

# ---------------------------------------------------------------------------
grp "8. Every file a README links to exists"

for md in $(git ls-files '*.md'); do
  dir=$(dirname "$md")
  # Relative links only; skip anchors, URLs, and mailto.
  grep -oE '\]\(([^)#][^)]*)\)' "$md" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//' | while read -r ref; do
    case "$ref" in
      http*|mailto:*|\#*|"") continue ;;
    esac
    target="${ref%%#*}"
    [ -z "$target" ] && continue
    if [ ! -e "$dir/$target" ]; then
      printf '  %s✗%s %s -> %s\n' "$_r" "$_0" "$md" "$target"
      echo x >> /tmp/selftest_linkfail
    fi
  done
done
if [ -f /tmp/selftest_linkfail ]; then
  fail=$((fail + $(wc -l < /tmp/selftest_linkfail)))
  rm -f /tmp/selftest_linkfail
else
  ok "all relative links in markdown resolve"
fi

# ---------------------------------------------------------------------------
grp "9. gxr works from the paths the docs use"

if ./gxr list >/dev/null 2>&1; then ok "./gxr list works from repo root"
else bad "./gxr list fails from repo root"; fi

d=$(demos | head -1)
if [ -z "$d" ]; then
  ok "no demos yet — skipping the in-demo path check (fine for a fresh template)"
elif (cd "$d" && ../../gxr list >/dev/null 2>&1); then
  ok "../../gxr works from inside a demo dir (as the READMEs instruct)"
else
  bad "../../gxr fails from inside a demo dir" "demo READMEs tell people to run it that way"
fi

# Capture first: with `set -o pipefail`, piping a deliberately-failing command
# into grep reports the pipeline as failed even when grep matched.
out=$(./gxr up __nonexistent__ 2>&1); rc=$?
if [ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'REMEDIATION:'; then
  ok "gxr rejects an unknown demo with remediation"
else
  bad "gxr does not fail cleanly on an unknown demo" "exit=$rc"
fi

# ---------------------------------------------------------------------------
grp "10. Cost claims are consistent"
# The README, demo.yaml, and handoff block must agree. People plan around these.

for d in $(demos); do
  slug=$(basename "$d")
  y=$(sed -n 's/^ *estimate_usd: *//p' "$d/demo.yaml" | head -1)
  [ -z "$y" ] && { bad "$slug: demo.yaml has no cost.estimate_usd"; continue; }
  # Formatted the way the handoff block prints it.
  printed=$(printf '%.2f' "$y")
  if grep -qE "Cost so far: ~\\\\?\\\$$printed" "$d/scripts/handoff.sh" \
     || grep -qE "\\\$$printed|\\\$$y\b" "$d/scripts/handoff.sh"; then
    ok "$slug cost agrees between demo.yaml and handoff.sh (\$$printed)"
  else
    bad "$slug: demo.yaml says \$$printed but handoff.sh prints something else" \
        "$(grep -o 'Cost so far[^.]*' "$d/scripts/handoff.sh" | head -1)"
  fi
done

# ---------------------------------------------------------------------------
printf '\n'
if [ "$fail" -eq 0 ]; then
  printf '%s%d passed, 0 failed%s\n\n' "$_g" "$pass" "$_0"
  exit 0
fi
printf '%s%d passed, %d FAILED%s\n\n' "$_r" "$pass" "$fail" "$_0"
exit 1
