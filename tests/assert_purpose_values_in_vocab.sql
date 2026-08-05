-- Warn when agent_purpose values fall outside the agent classification
-- enrichment vocabulary. Warn-only, since new categories may appear upstream.
{{ config(severity='warn') }}

select distinct agent_purpose
from {{ ref('agent_pageviews_daily') }}
where agent_purpose is not null
  and agent_purpose not in (
    'AI_TRAINING',
    'AI_USER_FETCH',
    'AI_SEARCH_INDEX',
    'SEARCH_INDEX',
    'LINK_PREVIEW'
  )
