{%- set snapshot_mode = var('summary_snapshot_mode', 'weekly') -%}

{{
  config(
    materialized=('table' if snapshot_mode == 'latest' else 'incremental'),
    unique_key=['agent_operator', 'as_of_date'],
    post_hook=(["delete from {{ this }} where as_of_date < dateadd(week, -" ~ var('summary_snapshot_retention_weeks', 26) ~ ", current_date)"] if snapshot_mode != 'latest' else [])
  )
}}

-- Both CTEs scan pre-aggregated daily tables. The referral side reads from
-- human_referrals_daily (already attributed to operators during daily
-- aggregation), avoiding a re-join against the operator seed at summary time.
with crawl_side as (
  select
    agent_operator,
    sum(case when event_date >= {{ as_of_date() }} - 7  then hits else 0 end) as crawl_hits_7d,
    sum(case when event_date >= {{ as_of_date() }} - 30 then hits else 0 end) as crawl_hits_30d,
    sum(case when event_date >= {{ as_of_date() }} - 90 then hits else 0 end) as crawl_hits_90d,
    count(distinct case when event_date >= {{ as_of_date() }} - 30 then agent_name end) as distinct_agent_names_30d,
    count(distinct case when event_date >= {{ as_of_date() }} - 30 then page_url_host_path end) as distinct_pages_crawled_30d,
    sum(case when event_date >= {{ as_of_date() }} - 30 and agent_purpose = 'AI_TRAINING'     then hits else 0 end) as ai_training_hits_30d,
    sum(case when event_date >= {{ as_of_date() }} - 30 and agent_purpose = 'AI_USER_FETCH'   then hits else 0 end) as ai_user_fetch_hits_30d,
    sum(case when event_date >= {{ as_of_date() }} - 30 and agent_purpose = 'AI_SEARCH_INDEX' then hits else 0 end) as ai_search_index_hits_30d,
    sum(case when event_date >= {{ as_of_date() }} - 30
             and (agent_purpose is null or agent_purpose not in ('AI_TRAINING', 'AI_USER_FETCH', 'AI_SEARCH_INDEX', 'SEARCH_INDEX')) then hits else 0 end) as other_purpose_hits_30d,
    min(first_seen_tstamp) as first_crawl_tstamp,
    max(last_seen_tstamp)  as last_crawl_tstamp
  from {{ ref('agent_pageviews_daily') }}
  -- The upper bound keeps windows honest: in weekly mode as_of_date is the Monday
  -- of the current week, and without it mid-week runs would fold days after the
  -- snapshot date into the "7d/30d/90d" windows (up to 13 days in a "7d" window).
  where event_date >= {{ as_of_date() }} - 90
    and event_date <= {{ as_of_date() }}
  group by 1
),

referral_side as (
  select
    referring_operator as agent_operator,
    sum(case when event_date >= {{ as_of_date() }} - 7  then referred_pageviews else 0 end) as referred_pageviews_7d,
    sum(case when event_date >= {{ as_of_date() }} - 30 then referred_pageviews else 0 end) as referred_pageviews_30d,
    sum(case when event_date >= {{ as_of_date() }} - 90 then referred_pageviews else 0 end) as referred_pageviews_90d,
    sum(case when event_date >= {{ as_of_date() }} - 7  then referred_sessions else 0 end) as referred_sessions_7d,
    sum(case when event_date >= {{ as_of_date() }} - 30 then referred_sessions else 0 end) as referred_sessions_30d,
    sum(case when event_date >= {{ as_of_date() }} - 90 then referred_sessions else 0 end) as referred_sessions_90d,
    count(distinct case when event_date >= {{ as_of_date() }} - 30 then page_url_host_path end) as distinct_referred_pages_30d,
    min(first_seen_tstamp) as first_referral_tstamp,
    max(last_seen_tstamp)  as last_referral_tstamp
  from {{ ref('human_referrals_daily') }}
  where event_date >= {{ as_of_date() }} - 90
    and event_date <= {{ as_of_date() }}
  group by 1
)

-- FULL OUTER JOIN is deliberate: operators that only crawl or only refer should still appear.
select
  coalesce(c.agent_operator, r.agent_operator) as agent_operator,
  {{ as_of_date() }} as as_of_date,
  coalesce(c.crawl_hits_7d, 0) as crawl_hits_7d,
  coalesce(c.crawl_hits_30d, 0) as crawl_hits_30d,
  coalesce(c.crawl_hits_90d, 0) as crawl_hits_90d,
  coalesce(c.distinct_agent_names_30d, 0) as distinct_agent_names_30d,
  coalesce(c.distinct_pages_crawled_30d, 0) as distinct_pages_crawled_30d,
  coalesce(c.ai_training_hits_30d, 0) as ai_training_hits_30d,
  coalesce(c.ai_user_fetch_hits_30d, 0) as ai_user_fetch_hits_30d,
  coalesce(c.ai_search_index_hits_30d, 0) as ai_search_index_hits_30d,
  coalesce(c.other_purpose_hits_30d, 0) as other_purpose_hits_30d,
  coalesce(r.referred_pageviews_7d, 0) as referred_pageviews_7d,
  coalesce(r.referred_pageviews_30d, 0) as referred_pageviews_30d,
  coalesce(r.referred_pageviews_90d, 0) as referred_pageviews_90d,
  coalesce(r.referred_sessions_7d, 0) as referred_sessions_7d,
  coalesce(r.referred_sessions_30d, 0) as referred_sessions_30d,
  coalesce(r.referred_sessions_90d, 0) as referred_sessions_90d,
  coalesce(r.distinct_referred_pages_30d, 0) as distinct_referred_pages_30d,
  {{ dbt_utils.safe_divide('coalesce(c.crawl_hits_30d, 0)', 'coalesce(r.referred_sessions_30d, 0)') }} as crawl_to_referral_ratio_30d,
  c.first_crawl_tstamp, c.last_crawl_tstamp,
  r.first_referral_tstamp, r.last_referral_tstamp,
  (least(coalesce(c.first_crawl_tstamp, r.first_referral_tstamp),
         coalesce(r.first_referral_tstamp, c.first_crawl_tstamp)) >= {{ as_of_date() }} - 7) as is_new_operator_7d
from crawl_side c
full outer join referral_side r using (agent_operator)
