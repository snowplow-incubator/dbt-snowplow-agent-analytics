{{
  config(
    materialized='table',
    tags=["this_run"],
    post_hook=["{{ snowplow_utils.print_run_limits(this, 'snowplow_agent_analytics') }}"]
  )
}}

{%- set models_in_run = snowplow_utils.get_enabled_snowplow_models('snowplow_agent_analytics', base_events_table_name='base_events_this_run') -%}

{% set min_first_success,
      max_first_success,
      min_last_success,
      max_last_success,
      models_matched_from_manifest,
      sync_count,
      has_matched_all_models = snowplow_utils.get_incremental_manifest_status_t(ref('incremental_manifest'), models_in_run) -%}

{% set run_limits_query = snowplow_utils.get_run_limits_t(min_first_success,
                                                          max_first_success,
                                                          min_last_success,
                                                          max_last_success,
                                                          models_matched_from_manifest,
                                                          sync_count,
                                                          has_matched_all_models,
                                                          var("snowplow__start_date", "2024-01-01")) -%}

{{ run_limits_query }}
