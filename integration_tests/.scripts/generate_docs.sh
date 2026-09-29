#!/bin/bash
set -eo pipefail

# Builds the integration test project and generates the dbt docs site for the package.
#
# Expected input:
# -d (database) target for dbt. Only snowflake is supported for now.
# -o (output)   directory to write the site into. Defaults to ../docs.
# -p (publish)  commit the site onto the current HEAD and force-push it to origin/gh_pages,
#               as the publish-gh-pages workflow does. Uses a temporary worktree, so the
#               current checkout is left untouched.
#
# Run from the integration_tests directory. Without DBT_PROFILES_DIR set, dbt reads the
# integration_tests profile from ~/.dbt/profiles.yml.

DATABASE=snowflake
OUTPUT=../docs
PUBLISH=false

while getopts 'd:o:p' opt
do
  case $opt in
    d) DATABASE=$OPTARG ;;
    o) OUTPUT=$OPTARG ;;
    p) PUBLISH=true ;;
  esac
done

if [[ $PUBLISH == true ]]; then
  WORKTREE=$(mktemp -d)
  git worktree add --detach "$WORKTREE" HEAD
  trap 'git worktree remove --force "$WORKTREE"' EXIT
  OUTPUT="$WORKTREE/docs"
fi

STG="snowplow_agent_analytics_events_stg"
INT_PROJECT="snowplow_agent_analytics_integration_tests"

dbt deps
dbt seed --target "$DATABASE" --full-refresh

# The stg model is read through source(), not ref(), so dbt can't order it -- build it first
dbt run --target "$DATABASE" --select $STG

# A single run with the backfill limit raised past the fixture's 100-day span builds every
# model; the catalog only needs the tables to exist, not the incremental sequence.
dbt run --target "$DATABASE" --full-refresh --exclude $STG --vars '{snowplow__backfill_limit_days: 120}'
dbt docs generate --target "$DATABASE" --vars '{snowplow__backfill_limit_days: 120}'

# Drop the integration test project's own nodes (fixture seeds, *_actual/*_expected models,
# equality tests) so the site documents only the package.
FILTER='walk(if type == "object" then with_entries(select(.key | contains("'$INT_PROJECT'") | not)) else . end)'

mkdir -p "$OUTPUT"
jq "$FILTER" target/manifest.json > "$OUTPUT/manifest.json"
jq "$FILTER" target/catalog.json > "$OUTPUT/catalog.json"
cp target/run_results.json target/index.html "$OUTPUT/"

echo "dbt docs written to $OUTPUT"

if [[ $PUBLISH == true ]]; then
  git -C "$WORKTREE" add docs/catalog.json docs/manifest.json docs/run_results.json docs/index.html
  git -C "$WORKTREE" commit -m 'Update dbt docs'
  git -C "$WORKTREE" push origin HEAD:refs/heads/gh_pages --force
  echo "Published to origin/gh_pages"
fi
