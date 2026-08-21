{# Worth asserting on directly: this table decides whether each agent is counted from
   CDN or client events, and its "never flip back" invariant only shows up across
   several incremental runs. #}
select
  agent_name,
  agent_runs_js,
  source_channel,
  last_seen_tstamp

from {{ ref('int_agent_source_lookup') }}
