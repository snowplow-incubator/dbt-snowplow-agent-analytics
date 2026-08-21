#!/bin/bash
set -o pipefail

# Expected input:
# -d (database) target database for dbt. Only snowflake is supported for now.

while getopts 'd:' opt
do
  case $opt in
    d) DATABASE=$OPTARG
  esac
done

declare -a SUPPORTED_DATABASES=("snowflake")

DATABASE="$(echo "$DATABASE" | tr '[:upper:]' '[:lower:]')"

if [[ $DATABASE == "all" || -z $DATABASE ]]; then
  DATABASES=( "${SUPPORTED_DATABASES[@]}" )
else
  DATABASES=( "$DATABASE" )
fi

for db in "${DATABASES[@]}"; do

  echo "snowplow_agent_analytics integration tests: Seeding data"

  eval "dbt seed --target $db --full-refresh" || exit 1;

  STG="snowplow_agent_analytics_events_stg"

  echo "snowplow_agent_analytics integration tests: Build source stage"

  eval "dbt run --target $db --select $STG" || exit 1;

  echo "snowplow_agent_analytics integration tests: Execute models - run 1/4 (full refresh)"

  eval "dbt run --target $db --full-refresh --exclude $STG" || exit 1;

  # Test dataset spans 100 days, backfill limit is 30 days => 4 runs needed for full backfill
  for i in {2..4}
  do
    echo "snowplow_agent_analytics integration tests: Execute models - run $i/4 (backfill)"

    eval "dbt run --target $db --exclude $STG" || exit 1;
  done

  echo "snowplow_agent_analytics integration tests: Test models"

  eval "dbt test --target $db" || exit 1;

  echo "snowplow_agent_analytics integration tests: All tests passed"

done
