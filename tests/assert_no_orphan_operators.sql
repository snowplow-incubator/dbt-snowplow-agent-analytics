-- Warn when an AI-purpose operator seen crawling has no rows in the
-- operator_referral_sources seed: its human referrals cannot be attributed,
-- so its crawl-to-referral ratio would be misleadingly infinite.
--
-- Operators listed in operators_without_referrals are exempt: they run AI
-- crawlers but no product that sends readers back, so there is nothing to map
-- and an unattributable ratio is the honest answer rather than a config gap.
{{ config(severity='warn') }}

select distinct a.agent_operator
from {{ ref('agent_pageviews_daily') }} a
where a.purpose_group = 'AI'
  and a.agent_operator is not null
  and not exists (
    select 1
    from {{ ref('operator_referral_sources') }} s
    where s.operator = a.agent_operator
  )
  and not exists (
    select 1
    from {{ ref('operators_without_referrals') }} n
    where n.operator = a.agent_operator
  )
