{{
  config(
    materialized='view'
  )
}}

-- One source per agent: JS-capable agents are counted from client-side
-- events, all other agents from CDN events. Deduplication has already been
-- applied in the base layer.
with client_side as (
  select 'client' as source_channel, e.*
  from {{ ref('base_events') }} e
  join {{ ref('int_agent_source_lookup') }} l
    on e.agent_name = l.agent_name
   and l.source_channel = 'client'
  where e.is_bot = true
    and e.raw_source_channel = 'client'
),

cdn_side as (
  select 'cdn' as source_channel, e.*
  from {{ ref('base_events') }} e
  join {{ ref('int_agent_source_lookup') }} l
    on e.agent_name = l.agent_name
   and l.source_channel = 'cdn'
  where e.is_bot = true
    and e.raw_source_channel = 'cdn'
)

select * from client_side
union all
select * from cdn_side
