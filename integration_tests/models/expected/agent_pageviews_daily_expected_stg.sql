select
  event_date,
  agent_name,
  agent_operator,
  agent_purpose,
  purpose_group,
  source_channel,
  page_url_host_path,
  hits,
  first_seen_tstamp,
  last_seen_tstamp

from {{ ref('agent_pageviews_daily_expected') }}
