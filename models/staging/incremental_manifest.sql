{{
  config(
    materialized='incremental',
    full_refresh=snowplow_agent_analytics.allow_refresh()
  )
}}

{{ snowplow_utils.base_create_snowplow_incremental_manifest_t() }}
