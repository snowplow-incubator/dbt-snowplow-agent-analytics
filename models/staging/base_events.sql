{# Upsert by event_id so manifest replays replace prior copies. BigQuery and
   Databricks use merge; Snowflake uses delete+insert. The
   snowplow_optimize meta bounds the target scan to the batch's load_tstamp range. #}
{# full_refresh guard: an accidental --full-refresh would truncate this table while
   the incremental manifest survives, so history would never be reprocessed. Refresh
   requires snowplow__allow_refresh (or the dev target), same as the manifest. #}
{{
  config(
    materialized='incremental',
    incremental_strategy=('merge' if target.type in ['bigquery', 'databricks'] else 'delete+insert'),
    unique_key='event_id',
    partition_by=snowplow_utils.get_value_by_target_type(
      bigquery_val={'field': 'load_tstamp', 'data_type': 'timestamp'},
      databricks_val='load_tstamp_date'
    ),
    meta={'upsert_date_key': ('load_tstamp_date' if target.type == 'databricks' else 'load_tstamp'), 'snowplow_optimize': true},
    on_schema_change='append_new_columns',
    full_refresh=snowplow_agent_analytics.allow_refresh(),
    tags=['snowplow_agent_analytics_incremental']
  )
}}

{%- if is_incremental() -%}
  {%- set columns = adapter.get_columns_in_relation(this) | map(attribute='name') | map('lower') | list -%}
  {%- if 'utm_source' not in columns or 'utm_medium' not in columns or 'load_tstamp_date' not in columns -%}
    {{ exceptions.raise_compiler_error(
      "Agent Analytics base_events needs an upgrade to populate extracted entity fields. "
      ~ "Follow the README upgrade instructions: migrate an existing Snowflake base table in place, "
      ~ "or retain source history and rebuild the whole package with --full-refresh and "
      ~ "snowplow__allow_refresh: true. Do not full-refresh base_events alone."
    ) }}
  {%- endif -%}
{%- endif -%}

select
  event_id,
  event_fingerprint,
  app_id,
  collector_tstamp,
  derived_tstamp,
  load_tstamp,
  load_tstamp_date,
  domain_sessionid,
  page_urlhost,
  page_urlpath,
  refr_source,
  refr_medium,
  utm_source,
  utm_medium,
  is_bot,
  raw_source_channel,
  agent_name,
  agent_operator,
  agent_purpose
from {{ ref('base_events_this_run') }}
