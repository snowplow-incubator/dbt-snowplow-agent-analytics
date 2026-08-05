-- Every agent_name that appears in base_events with is_bot = true must have
-- exactly one row in int_agent_source_lookup with a valid source_channel.
with bot_agents as (
  select distinct {{ agent_name('e') }} as agent_name
  from {{ ref('base_events') }} e
  where e.is_bot = true
    and {{ agent_name('e') }} is not null
),

lookup_rows as (
  select
    agent_name,
    count(*) as row_count,
    count_if(source_channel in ('cdn', 'client')) as valid_channel_count
  from {{ ref('int_agent_source_lookup') }}
  group by 1
)

select b.agent_name, l.row_count, l.valid_channel_count
from bot_agents b
left join lookup_rows l
  on b.agent_name = l.agent_name
where l.agent_name is null
   or l.row_count != 1
   or l.valid_channel_count != 1
