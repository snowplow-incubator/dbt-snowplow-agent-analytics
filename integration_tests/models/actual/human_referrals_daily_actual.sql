select
  event_date,
  referring_operator,
  page_url_host_path,
  referred_pageviews,
  referred_sessions,
  first_seen_tstamp,
  last_seen_tstamp

from {{ ref('human_referrals_daily') }}
