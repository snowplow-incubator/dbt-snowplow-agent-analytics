{# delete+insert on event_date gives partition-overwrite semantics on Snowflake:
   each batch recomputes complete trailing days from base_events, deletes those
   dates from the target, and inserts the fresh aggregates. #}
{{
  config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='event_date',
    meta={'upsert_date_key': 'event_date', 'snowplow_optimize': true},
    cluster_by=['page_url_host_path'],
    on_schema_change='append_new_columns',
    tags=['snowplow_agent_analytics_incremental']
  )
}}

{# Hoisted out of the is_incremental() block: refs inside a branch that does not
   render at parse time are not captured as dependencies. #}
{%- set base_events_this_run = ref('base_events_this_run') -%}

select
  date(e.derived_tstamp) as event_date,
  {{ page_url_host_path('e') }} as page_url_host_path,
  count(*) as human_pageviews,
  min(e.derived_tstamp) as first_seen_tstamp,
  max(e.derived_tstamp) as last_seen_tstamp
from {{ ref('base_events') }} e
where e.is_bot = false
  and e.raw_source_channel = 'client'
  and date(e.derived_tstamp) >= {{ dbt_start_date() }}
  {% if is_incremental() %}
    -- Rebuild the late-data window, extended to cover every event_date present in
    -- this run's manifest batch: during backfill or failure replay the batch holds
    -- days far older than the trailing window, and anchoring on current_date alone
    -- would silently drop them from this table.
    and date(e.derived_tstamp) >= least(
      dateadd(day, -{{ var("late_data_window_days", 3) }}, current_date),
      coalesce((select min(date(derived_tstamp)) from {{ base_events_this_run }}), current_date)
    )
  {% endif %}
group by 1, 2
