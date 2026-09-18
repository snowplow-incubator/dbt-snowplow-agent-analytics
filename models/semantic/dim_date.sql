{# Conformed date dimension. No fact table is unique on event_date, so none of them can
   serve as the "one" side of a date join -- this is what the facts group by. #}
{{
  config(
    materialized='table',
    enabled=var('enable_semantic_views', false)
  )
}}

with dates as (
  select event_date from {{ ref('agent_pageviews_daily') }}
  union
  select event_date from {{ ref('human_pageviews_daily') }}
  union
  select event_date from {{ ref('human_referrals_daily') }}
)

select
  event_date,
  {{ dbt.date_trunc('week', 'event_date') }} as week_start_date,
  {{ dbt.date_trunc('month', 'event_date') }} as month_start_date,
  {{ dbt.date_trunc('quarter', 'event_date') }} as quarter_start_date,
  {{ dbt.date_trunc('year', 'event_date') }} as year_start_date
from dates
where event_date is not null
