{# Snapshot date for the summary tables.
   snowplow__as_of_date -> pinned to that literal date. Set this to make the 7/30/90d
              windows reproducible: integration tests need a stable answer, and a
              backfill/replay wants the windows anchored to the date being rebuilt
              rather than to whenever the run happens to execute.
   weekly  -> Monday of the current week (one snapshot per week; mid-week runs refresh it,
              but the summaries only include event_date <= as_of_date, so the row is
              stable once Monday's data has finished loading)
   latest / daily -> current_date #}
{% macro as_of_date() -%}
    {%- set pinned = var('snowplow__as_of_date', none) -%}
    {%- if pinned -%}
        to_date('{{ pinned }}')
    {%- elif var('summary_snapshot_mode', 'weekly') == 'weekly' -%}
        date_trunc('week', current_date)
    {%- else -%}
        current_date
    {%- endif -%}
{%- endmacro %}
