#!/bin/bash
# Regenerate every data/expected/*.csv seed from the currently-built *_actual models.
#
# Run this only after `dbt seed` + the full run sequence in integration_tests.sh has
# succeeded, and ALWAYS read `git diff data/expected/` before committing: this script
# freezes whatever the models currently emit, so an unreviewed diff can turn a bug into
# the expected answer.
set -euo pipefail

TARGET="${1:-snowflake}"

MODELS=(
  int_agent_source_lookup
  agent_pageviews_daily
  human_pageviews_daily
  human_referrals_daily
  page_summary
  operator_summary
)

mkdir -p data/expected

for m in "${MODELS[@]}"; do
  echo "dumping ${m}_actual -> data/expected/${m}_expected.csv" >&2
  dbt run-operation dump_expected \
      --args "{model: ${m}_actual}" \
      --target "$TARGET" --quiet \
      > "data/expected/${m}_expected.csv"
  lines=$(( $(wc -l < "data/expected/${m}_expected.csv") - 1 ))
  echo "  ${lines} rows" >&2
done

echo "done. now review: git diff data/expected/" >&2
