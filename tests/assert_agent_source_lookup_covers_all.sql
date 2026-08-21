-- int_agent_source_lookup must hold exactly the agents its admission rules allow:
-- bot-flagged in CDN at some point, and not on the ignore list. Each of the three ways
-- that can break is reported with a reason, so a failure says what actually went wrong.
--
-- Flags are computed over the whole of base_events, not one batch, because both the
-- lookup and the admission rules are lifetime properties of an agent.
with bot_agents as (
  select
    e.agent_name,
    boolor_agg(e.raw_source_channel = 'cdn') as seen_in_cdn,
    boolor_agg(e.raw_source_channel = 'client') as seen_in_client
  from {{ ref('base_events') }} e
  where e.is_bot = true
    and e.agent_name is not null
  group by 1
),

ignored as (
  select agent_name
  from {{ ref('agent_name_ignore_list') }}
  where agent_name is not null
),

eligible as (
  select agent_name
  from bot_agents
  where seen_in_cdn
    and agent_name not in (select agent_name from ignored)
),

lookup_rows as (
  select
    agent_name,
    count(*) as row_count,
    count_if(source_channel in ('cdn', 'client')) as valid_channel_count
  from {{ ref('int_agent_source_lookup') }}
  group by 1
)

-- 1. an agent that should be counted is absent, duplicated, or has a bad channel
select
  e.agent_name,
  'eligible agent missing, duplicated, or has an invalid source_channel' as failure
from eligible e
left join lookup_rows l on e.agent_name = l.agent_name
where l.agent_name is null
   or l.row_count != 1
   or l.valid_channel_count != 1

union all

-- 2. a generic name leaked past the ignore list, which is what would drag unrelated
--    client-side datacenter traffic into the agent marts
select
  l.agent_name,
  'ignore-listed agent present in lookup' as failure
from lookup_rows l
join ignored i on l.agent_name = i.agent_name

union all

-- 3. an agent never bot-flagged in CDN got in, meaning it was identified by something
--    other than its user agent (asnLookups / clientSideDetection) and has no real identity
select
  l.agent_name,
  'agent never bot-flagged in CDN present in lookup' as failure
from lookup_rows l
join bot_agents b on l.agent_name = b.agent_name
where not b.seen_in_cdn
