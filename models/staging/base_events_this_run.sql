{{
  config(
    materialized='table',
    tags=["this_run"]
  )
}}

{# Single quotes in app_ids are escaped so a value like "o'reilly" cannot break the
   generated SQL. (Values containing '--' are still rejected by the macro's unsafe-SQL
   check on custom_filter.) #}
{%- set cdn_app_ids = var('cdn_app_ids', ['cdn']) -%}
{%- set cdn_app_ids_csv = "'" ~ cdn_app_ids | map('replace', "'", "''") | join("', '") ~ "'" -%}

{# The source() lookup keeps lineage real: the _t macro below addresses the events
   table by database/schema/identifier strings, so without this the source would
   never appear in the DAG. #}
{%- set events_source = source('snowplow', 'events') -%}

{# Standard snowplow-utils macro for timestamp-based event selection. Filters by
   load_tstamp, ensuring partition/cluster pruning on modern loaders, and removes
   same-batch event_id duplicates (earliest by load_tstamp). Note this collapses
   synthetic duplicates (same event_id, different fingerprint) for CDN rows too,
   before the fingerprint dedup below; CDN hit counts are a conservative lower bound either way. The row filter
   is pushed down into the raw scan via custom_filter. #}
{%- set base_events_query = snowplow_utils.base_create_snowplow_events_this_run_t(
    run_limits_table='base_new_event_limits',
    app_ids=[],
    snowplow_events_database=events_source.database,
    snowplow_events_schema=events_source.schema,
    snowplow_events_table=events_source.identifier,
    event_names=[],
    custom_filter="(app_id in (" ~ cdn_app_ids_csv ~ ") or (platform = 'web' and event_name = 'page_view'))"
) -%}

with raw_events as (
  {{ base_events_query }}
),

source_events as (
  select
    e.*,
    {{ bot_flag('e') }} as is_bot,
    case
      when e.app_id in ({{ cdn_app_ids_csv }}) then 'cdn'
      when e.platform = 'web' then 'client'
    end as raw_source_channel
  from raw_events e
),

-- Dedup within the batch. The client-side pass is
-- defensive only: the macro above already deduped the whole batch on event_id.
client_deduped as (
  select *
  from source_events
  where raw_source_channel = 'client'
  qualify row_number() over (partition by event_id order by collector_tstamp) = 1
),

cdn_deduped as (
  select *
  from source_events
  where raw_source_channel = 'cdn'
  qualify row_number() over (
    partition by coalesce(event_fingerprint, event_id)
    order by collector_tstamp
  ) = 1
)

select * from client_deduped
union all
select * from cdn_deduped
