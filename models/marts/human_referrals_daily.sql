{# Recompute complete dates from the durable base. BigQuery replaces date
   partitions; other adapters delete+insert by event_date. This also removes
   obsolete groups when an agent changes source channel. #}
{{
  config(
    materialized='incremental',
    incremental_strategy=('insert_overwrite' if target.type == 'bigquery' else 'delete+insert'),
    partition_by=({'field': 'event_date', 'data_type': 'date'} if target.type == 'bigquery' else none),
    unique_key='event_date',
    meta={'upsert_date_key': 'event_date', 'snowplow_optimize': true},
    cluster_by=(['referring_operator', 'page_url_host_path'] if target.type in ['snowflake', 'bigquery'] else none),
    on_schema_change='append_new_columns',
    tags=['snowplow_agent_analytics_incremental']
  )
}}

{# Hoisted out of the is_incremental() block: refs inside a branch that does not
   render at parse time are not captured as dependencies. #}
{%- set base_events_this_run = ref('base_events_this_run') -%}

-- Referral attribution: prefer the utm_referrer entity over refr_* fields —
-- UTM-tagged links carry deliberate attribution intent from the AI platform, and
-- Referer headers are more often stripped or rewritten.
select
  date(e.derived_tstamp) as event_date,
  s.operator as referring_operator,
  {{ page_url_host_path('e') }} as page_url_host_path,
  count(*) as referred_pageviews,
  count(distinct e.domain_sessionid) as referred_sessions,
  min(e.derived_tstamp) as first_seen_tstamp,
  max(e.derived_tstamp) as last_seen_tstamp
from {{ ref('base_events') }} e
join {{ ref('operator_referral_sources') }} s
  on lower(coalesce(e.utm_source, e.refr_source)) = lower(s.source_value)
 and (s.medium_value is null
      or lower(coalesce(e.utm_medium, e.refr_medium)) = lower(s.medium_value))
where e.is_bot = false
  and e.raw_source_channel = 'client'
  and date(e.derived_tstamp) >= {{ dbt_start_date() }}
  {% if is_incremental() %}
    -- Rebuild the late-data window, extended to cover every event_date present in
    -- this run's manifest batch: during backfill or failure replay the batch holds
    -- days far older than the trailing window, and anchoring on current_date alone
    -- would silently drop them from this table.
    and date(e.derived_tstamp) >= least(
      cast({{ dbt.dateadd('day', -(var('late_data_window_days', 3) | int), 'current_date') }} as date),
      coalesce((select min(date(derived_tstamp)) from {{ base_events_this_run }}), current_date)
    )
  {% endif %}
group by 1, 2, 3
