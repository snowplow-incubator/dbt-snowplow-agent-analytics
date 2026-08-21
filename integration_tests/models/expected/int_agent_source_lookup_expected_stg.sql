select
  agent_name,
  agent_runs_js,
  source_channel,
  last_seen_tstamp

from {{ ref('int_agent_source_lookup_expected') }}
