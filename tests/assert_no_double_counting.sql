-- SUM(hits) in agent_pageviews_daily for a given (event_date, agent_name) must
-- equal the count of deduplicated events for that agent from whichever source
-- int_agent_source_lookup assigns. Restricted to the late-data window:
-- older partitions are frozen and may legitimately predate a cdn -> client flip.
{{ config(severity='warn') }}

with expected as (
  select
    date(u.derived_tstamp) as event_date,
    u.agent_name,
    count(*) as expected_hits
  from {{ ref('int_agent_pageviews_unified') }} u
  where date(u.derived_tstamp) >= dateadd(day, -{{ var('late_data_window_days', 3) }}, current_date)
  group by 1, 2
),

actual as (
  select
    event_date,
    agent_name,
    sum(hits) as actual_hits
  from {{ ref('agent_pageviews_daily') }}
  where event_date >= dateadd(day, -{{ var('late_data_window_days', 3) }}, current_date)
  group by 1, 2
)

select
  coalesce(e.event_date, a.event_date) as event_date,
  coalesce(e.agent_name, a.agent_name) as agent_name,
  coalesce(e.expected_hits, 0) as expected_hits,
  coalesce(a.actual_hits, 0) as actual_hits
from expected e
full outer join actual a
  on e.event_date = a.event_date
 and e.agent_name = a.agent_name
where coalesce(e.expected_hits, 0) != coalesce(a.actual_hits, 0)
