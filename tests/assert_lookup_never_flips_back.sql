-- The lookup must never assign 'cdn' to an agent that has ever fired
-- client-side bot events: once JS-capable, always counted client-side.
with client_bot_agents as (
  select distinct e.agent_name
  from {{ ref('base_events') }} e
  where e.is_bot = true
    and e.raw_source_channel = 'client'
    and e.agent_name is not null
)

select l.agent_name, l.source_channel
from {{ ref('int_agent_source_lookup') }} l
join client_bot_agents c
  on l.agent_name = c.agent_name
where l.source_channel != 'client'
