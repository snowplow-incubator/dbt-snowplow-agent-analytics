{# delete+insert on event_date gives partition-overwrite semantics on Snowflake:
   each batch recomputes complete trailing days from base_events, deletes those
   dates from the target, and inserts the fresh aggregates. #}
{{
  config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='event_date',
    meta={'upsert_date_key': 'event_date', 'snowplow_optimize': true},
    cluster_by=['agent_operator', 'page_url_host_path'],
    on_schema_change='append_new_columns',
    tags=['snowplow_agent_analytics_incremental']
  )
}}

{# Hoisted out of the is_incremental() block: refs inside a branch that does not
   render at parse time are not captured as dependencies. #}
{%- set base_events_this_run = ref('base_events_this_run') -%}

with source as (
  select
    date(u.derived_tstamp) as event_date,
    u.agent_name,
    coalesce(u.agent_operator, 'unknown') as agent_operator,
    u.agent_purpose,
    {{ purpose_group_case('u.agent_purpose') }} as purpose_group,
    u.source_channel,
    {{ page_url_host_path('u') }} as page_url_host_path,
    u.derived_tstamp
  from {{ ref('int_agent_pageviews_unified') }} u
  where date(u.derived_tstamp) >= {{ dbt_start_date() }}
  {% if is_incremental() %}
    -- Rebuild the late-data window, extended to cover every event_date present in
    -- this run's manifest batch: during backfill or failure replay the batch holds
    -- days far older than the trailing window, and anchoring on current_date alone
    -- would silently drop them from this table.
    and date(u.derived_tstamp) >= least(
      dateadd(day, -{{ var("late_data_window_days", 3) }}, current_date),
      coalesce((select min(date(derived_tstamp)) from {{ base_events_this_run }}), current_date)
    )
  {% endif %}
)

select
  event_date,
  agent_name,
  agent_operator,
  agent_purpose,
  purpose_group,
  source_channel,
  page_url_host_path,
  count(*) as hits,
  min(derived_tstamp) as first_seen_tstamp,
  max(derived_tstamp) as last_seen_tstamp
from source
group by all
