#!/usr/bin/env bash
# Create the database, apply the schema, load synthetic data, done.
# Idempotent: safe to re-run.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/lib/common.sh"
eval "$(parse_common_flags "$@")"
# shellcheck disable=SC2034  # read by the logging helpers in common.sh
GXR_STEP=setup
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step "Setup — building the graph"

load_env "$DEMO_DIR"
require_env GCP_PROJECT SPANNER_INSTANCE SPANNER_DATABASE SPANNER_GRAPH \
            FRAUD_CLIENTS FRAUD_TRANSACTIONS FRAUD_DAYS FRAUD_SEED

GEN_DIR="$DEMO_DIR/data/generated"

info "generating synthetic payments (seed $FRAUD_SEED — same seed, same graph)"
python3 "$DEMO_DIR/data/generate.py" \
  --out "$GEN_DIR" --seed "$FRAUD_SEED" --days "$FRAUD_DAYS" \
  --clients "$FRAUD_CLIENTS" --transactions "$FRAUD_TRANSACTIONS" >/dev/null \
  || die "Data generation failed." "Check that python3 is 3.9 or later: python3 --version"
ok "generated $(grep -c 'INSERT INTO' "$GEN_DIR/load.sql") batched INSERT statement(s)"

if gcloud spanner databases describe "$SPANNER_DATABASE" --instance="$SPANNER_INSTANCE" \
     --project="$GCP_PROJECT" >/dev/null 2>&1; then
  info "database $SPANNER_DATABASE already exists"
else
  gcloud spanner databases create "$SPANNER_DATABASE" \
    --instance="$SPANNER_INSTANCE" --project="$GCP_PROJECT" --quiet >/dev/null \
    || die "Could not create database $SPANNER_DATABASE." \
           "Check you have roles/spanner.databaseAdmin on $GCP_PROJECT."
  ok "created database $SPANNER_DATABASE"
fi

# Applying the DDL twice fails on "already exists", which is fine on a re-run.
info "applying schema and property graph"
ddl_out=$(gcloud spanner databases ddl update "$SPANNER_DATABASE" \
            --instance="$SPANNER_INSTANCE" --project="$GCP_PROJECT" \
            --ddl-file="$DEMO_DIR/sql/01_schema.ddl" --quiet 2>&1) || {
  case "$ddl_out" in
    *"Duplicate name"*|*"already exists"*)
      info "schema already applied" ;;
    *)
      printf '%s\n' "$ddl_out" >&2
      die "Applying the schema failed." "See the output above." ;;
  esac
}
ok "schema and property graph in place"

# Clear then load, so a re-run converges instead of duplicating rows.
info "clearing any previous rows"
for t in PaidMerchant Paid UsedDevice Merchant Device Client; do
  gcloud spanner databases execute-sql "$SPANNER_DATABASE" \
    --instance="$SPANNER_INSTANCE" --project="$GCP_PROJECT" \
    --sql="DELETE FROM $t WHERE TRUE" >/dev/null 2>&1 || true
done

info "loading rows (this is the slow part, ~1 min)"
n=0
while IFS= read -r stmt; do
  [ -z "$stmt" ] && continue
  gcloud spanner databases execute-sql "$SPANNER_DATABASE" \
    --instance="$SPANNER_INSTANCE" --project="$GCP_PROJECT" \
    --sql="$stmt" >/dev/null 2>&1 \
    || die "A load statement failed." "Re-run setup — it clears and reloads, so repeating is safe."
  n=$((n + 1))
done < <(python3 - "$GEN_DIR/load.sql" <<'PY'
import sys
# Split on the blank line between statements rather than on ';', which also
# appears inside the DDL comments, and emit each as one line for the shell loop.
text = open(sys.argv[1]).read()
for stmt in [s.strip() for s in text.split(";\n") if s.strip()]:
    print(" ".join(stmt.split()))
PY
)
ok "loaded $n batch(es)"
ok "setup complete"
