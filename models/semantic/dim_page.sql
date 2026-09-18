{# Conformed page dimension: the join bridge between agent traffic, human pageviews and
   referrals. #}
{{
  config(
    materialized='table',
    enabled=var('enable_semantic_views', false)
  )
}}

with pages as (
  select page_url_host_path from {{ ref('agent_pageviews_daily') }}
  union
  select page_url_host_path from {{ ref('human_pageviews_daily') }}
  union
  select page_url_host_path from {{ ref('human_referrals_daily') }}
)

select
  page_url_host_path,
  {{ dbt.split_part('page_url_host_path', "'/'", 1) }} as page_host,
  -- position() returns 0 for a bare host, which substr would read as "from the start"
  -- and hand back the host again.
  case
    when {{ dbt.position("'/'", 'page_url_host_path') }} > 0
      then substr(page_url_host_path, {{ dbt.position("'/'", 'page_url_host_path') }})
    else '/'
  end as page_path,
  {{ dbt.split_part('page_url_host_path', "'/'", 2) }} as page_section
from pages
where page_url_host_path is not null
