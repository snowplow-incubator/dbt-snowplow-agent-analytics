{%- set snapshot_mode = var('summary_snapshot_mode', 'weekly') -%}

{{
  config(
    materialized=('table' if snapshot_mode == 'latest' else 'incremental'),
    incremental_strategy='merge',
    unique_key=['page_url_host_path', 'as_of_date'],
    post_hook=(["{{ snowplow_agent_analytics.prune_snapshots() }}"] if snapshot_mode != 'latest' else [])
  )
}}

-- All three input CTEs read from small, pre-aggregated daily tables. No raw event scans.
with agent_windowed as (
  select
    page_url_host_path,
    sum(case when event_date >= cast({{ dbt.dateadd('day', -7, as_of_date()) }} as date)  then hits else 0 end) as agent_hits_7d,
    sum(case when event_date >= cast({{ dbt.dateadd('day', -30, as_of_date()) }} as date) then hits else 0 end) as agent_hits_30d,
    sum(case when event_date >= cast({{ dbt.dateadd('day', -90, as_of_date()) }} as date) then hits else 0 end) as agent_hits_90d,
    count(distinct case when event_date >= cast({{ dbt.dateadd('day', -30, as_of_date()) }} as date) then agent_operator end) as distinct_agent_operators_30d,
    count(distinct case when event_date >= cast({{ dbt.dateadd('day', -30, as_of_date()) }} as date) then agent_name end) as distinct_agent_names_30d,
    sum(case when event_date >= cast({{ dbt.dateadd('day', -30, as_of_date()) }} as date) and agent_purpose = 'AI_TRAINING'     then hits else 0 end) as ai_training_hits_30d,
    sum(case when event_date >= cast({{ dbt.dateadd('day', -30, as_of_date()) }} as date) and agent_purpose = 'AI_USER_FETCH'   then hits else 0 end) as ai_user_fetch_hits_30d,
    sum(case when event_date >= cast({{ dbt.dateadd('day', -30, as_of_date()) }} as date) and agent_purpose = 'AI_SEARCH_INDEX' then hits else 0 end) as ai_search_index_hits_30d,
    sum(case when event_date >= cast({{ dbt.dateadd('day', -30, as_of_date()) }} as date) and agent_purpose = 'SEARCH_INDEX'    then hits else 0 end) as search_index_hits_30d,
    min(first_seen_tstamp) as first_agent_visit_tstamp,
    max(last_seen_tstamp)  as last_agent_visit_tstamp
  from {{ ref('agent_pageviews_daily') }}
  -- The upper bound keeps windows honest: in weekly mode as_of_date is the Monday
  -- of the current week, and without it mid-week runs would fold days after the
  -- snapshot date into the "7d/30d/90d" windows (up to 13 days in a "7d" window).
  where event_date >= cast({{ dbt.dateadd('day', -90, as_of_date()) }} as date)
    and event_date <= {{ as_of_date() }}
  group by 1
),

human_windowed as (
  select
    page_url_host_path,
    sum(case when event_date >= cast({{ dbt.dateadd('day', -7, as_of_date()) }} as date)  then human_pageviews else 0 end) as human_pageviews_7d,
    sum(case when event_date >= cast({{ dbt.dateadd('day', -30, as_of_date()) }} as date) then human_pageviews else 0 end) as human_pageviews_30d,
    sum(case when event_date >= cast({{ dbt.dateadd('day', -90, as_of_date()) }} as date) then human_pageviews else 0 end) as human_pageviews_90d
  from {{ ref('human_pageviews_daily') }}
  where event_date >= cast({{ dbt.dateadd('day', -90, as_of_date()) }} as date)
    and event_date <= {{ as_of_date() }}
  group by 1
),

ai_referred as (
  select
    page_url_host_path,
    sum(referred_pageviews) as ai_referral_pageviews_30d,
    sum(referred_sessions) as ai_referral_sessions_30d
  from {{ ref('human_referrals_daily') }}
  where event_date >= cast({{ dbt.dateadd('day', -30, as_of_date()) }} as date)
    and event_date <= {{ as_of_date() }}
  group by 1
)

select
  coalesce(a.page_url_host_path, h.page_url_host_path) as page_url_host_path,
  {{ as_of_date() }} as as_of_date,
  coalesce(a.agent_hits_7d, 0) as agent_hits_7d,
  coalesce(a.agent_hits_30d, 0) as agent_hits_30d,
  coalesce(a.agent_hits_90d, 0) as agent_hits_90d,
  coalesce(a.distinct_agent_operators_30d, 0) as distinct_agent_operators_30d,
  coalesce(a.distinct_agent_names_30d, 0) as distinct_agent_names_30d,
  coalesce(a.ai_training_hits_30d, 0) as ai_training_hits_30d,
  coalesce(a.ai_user_fetch_hits_30d, 0) as ai_user_fetch_hits_30d,
  coalesce(a.ai_search_index_hits_30d, 0) as ai_search_index_hits_30d,
  coalesce(a.search_index_hits_30d, 0) as search_index_hits_30d,
  a.first_agent_visit_tstamp,
  a.last_agent_visit_tstamp,
  coalesce(h.human_pageviews_7d, 0) as human_pageviews_7d,
  coalesce(h.human_pageviews_30d, 0) as human_pageviews_30d,
  coalesce(h.human_pageviews_90d, 0) as human_pageviews_90d,
  coalesce(r.ai_referral_pageviews_30d, 0) as ai_referral_pageviews_30d,
  coalesce(r.ai_referral_sessions_30d, 0) as ai_referral_sessions_30d,
  (coalesce(a.agent_hits_30d, 0) >= {{ var('orphan_agent_hits_threshold', 10) }}
    and coalesce(h.human_pageviews_30d, 0) < {{ var('orphan_human_pageviews_threshold', 5) }}) as is_orphaned_agent_interest,
  {{ dbt_utils.safe_divide('coalesce(r.ai_referral_pageviews_30d, 0)', 'coalesce(a.ai_user_fetch_hits_30d, 0) + coalesce(a.ai_search_index_hits_30d, 0)') }} as cite_through_rate_proxy_30d
from agent_windowed a
full outer join human_windowed h using (page_url_host_path)
left join ai_referred r using (page_url_host_path)
