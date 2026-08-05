{# Snowflake's insert_overwrite truncates the whole table rather than replacing
   partitions, so the partition-overwrite intent of the spec is implemented as
   delete+insert keyed on event_id: reprocessed batches (manifest replays) delete
   their prior copies before inserting, keeping the table idempotent. The
   snowplow_optimize meta bounds the delete scan to the batch's load_tstamp range. #}
{# full_refresh guard: an accidental --full-refresh would truncate this table while
   the incremental manifest survives, so history would never be reprocessed. Refresh
   requires snowplow__allow_refresh (or the dev target), same as the manifest. #}
{{
  config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='event_id',
    meta={'upsert_date_key': 'load_tstamp', 'snowplow_optimize': true},
    on_schema_change='append_new_columns',
    full_refresh=snowplow_agent_analytics.allow_refresh(),
    tags=['snowplow_agent_analytics_incremental']
  )
}}

select * from {{ ref('base_events_this_run') }}
