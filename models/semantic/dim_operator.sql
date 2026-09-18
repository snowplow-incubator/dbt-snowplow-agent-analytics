{# Conformed operator dimension: the bridge that makes "does this operator crawl more
   than it refers?" one question rather than two. Unions both fact sides with both
   seeds, so operators that only crawl, only refer, or are merely known all get a row. #}
{{
  config(
    materialized='table',
    enabled=var('enable_semantic_views', false)
  )
}}

with operators as (
  select agent_operator as operator from {{ ref('agent_pageviews_daily') }}
  union
  select referring_operator from {{ ref('human_referrals_daily') }}
  union
  select operator from {{ ref('operator_referral_sources') }}
  union
  select operator from {{ ref('operators_without_referrals') }}
),

referral_sources as (
  select distinct operator from {{ ref('operator_referral_sources') }}
)

select
  o.operator,
  -- Distinguishes "sends no referrals" from "no referral sources configured".
  (s.operator is not null) as has_referral_sources,
  (n.operator is not null) as is_known_non_referring
from operators o
left join referral_sources s
  on o.operator = s.operator
left join {{ ref('operators_without_referrals') }} n
  on o.operator = n.operator
where o.operator is not null
