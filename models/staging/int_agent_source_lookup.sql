{# Unlike the spec, no snowplow_optimize/upsert_date_key here: bounding the merge
   scan by last_seen_tstamp would fail to match agents dormant longer than the
   upsert lookback and insert duplicate agent_name rows. The table holds one row
   per agent name, so an unbounded merge is cheap and always correct.

   full_refresh guard: this table accumulates per-agent JS-capability state; a
   rebuild would only see the current batch and forget which agents are client-side.
   Refresh requires snowplow__allow_refresh (or the dev target). #}
{{
  config(
    materialized='incremental',
    unique_key='agent_name',
    incremental_strategy='merge',
    full_refresh=snowplow_agent_analytics.allow_refresh(),
    tags=['snowplow_agent_analytics_incremental']
  )
}}

with new_bot_agents as (
  select
    e.agent_name,
    e.raw_source_channel,
    max(e.collector_tstamp) as last_seen_tstamp
  from {{ ref('base_events_this_run') }} e
  where e.is_bot = true
    and e.agent_name is not null
  group by 1, 2
),

-- Pivot: did this agent appear in CDN? In client?
agent_channels as (
  select
    agent_name,
    boolor_agg(raw_source_channel = 'client') as seen_in_client,
    boolor_agg(raw_source_channel = 'cdn') as seen_in_cdn,
    max(last_seen_tstamp) as last_seen_tstamp
  from new_bot_agents
  group by 1
),

new_lookup as (
  select
    agent_name,
    seen_in_client as agent_runs_js,
    case when seen_in_client then 'client' else 'cdn' end as source_channel,
    last_seen_tstamp
  from agent_channels
  -- Two guards, both resting on the fact that CDN-side bot detection has only the user
  -- agent string to work with.
  --
  -- seen_in_cdn: both flags are computed over is_bot = true rows, so this means "was
  -- bot-flagged in CDN", which on the CDN side can only have happened via the UA. An
  -- agent detected solely client-side was caught by asnLookups or clientSideDetection
  -- (datacenter IP ranges, automation markers) rather than by its UA, so it has no
  -- reliable identity and would enter here under a generic browser name.
  --
  -- ignore list: the failsafe for agent_ua_overrides being incomplete. A masquerading UA
  -- with no override still gets bot-flagged in CDN, which would set seen_in_cdn for e.g.
  -- 'Chrome' -- and that single row would then drag every client-side datacenter-Chrome
  -- event into the agent marts under the same name.
  where seen_in_cdn
    and agent_name not in (
      select agent_name
      from {{ ref('agent_name_ignore_list') }}
      where agent_name is not null   -- a NULL would make `not in` match nothing at all
    )
)

{% if is_incremental() %}
  -- Join against existing lookup to enforce "never flip back" invariant:
  -- if the agent was previously 'client', keep 'client' even if this batch
  -- only saw it in CDN events.
  select
    nl.agent_name,
    case
      when nl.agent_runs_js then true
      when existing.source_channel = 'client' then true
      else nl.agent_runs_js
    end as agent_runs_js,
    case
      when nl.source_channel = 'client' then 'client'
      when existing.source_channel = 'client' then 'client'
      else nl.source_channel
    end as source_channel,
    greatest(nl.last_seen_tstamp, coalesce(existing.last_seen_tstamp, nl.last_seen_tstamp)) as last_seen_tstamp
  from new_lookup nl
  left join {{ this }} existing on nl.agent_name = existing.agent_name
{% else %}
  select * from new_lookup
{% endif %}
