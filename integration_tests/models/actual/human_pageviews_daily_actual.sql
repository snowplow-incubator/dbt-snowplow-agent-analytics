select
  event_date,
  page_url_host_path,
  human_pageviews,
  first_seen_tstamp,
  last_seen_tstamp

from {{ ref('human_pageviews_daily') }}
