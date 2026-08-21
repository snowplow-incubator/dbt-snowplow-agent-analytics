{# Snowflake source stage for the integration-test fixture.

   dbt seeds every column as a scalar type, so the four self-describing entity columns
   arrive as varchar holding JSON text. The package's context macros address them as
   `col[0]:field::type`, which needs a real variant, so parse_json them here. Empty CSV
   fields seed as NULL and parse_json(NULL) is NULL, matching production rows where the
   enrichment attached no context.

   Snowflake-only for now; add sibling folders under models/source/ (and the matching
   +enabled flag in dbt_project.yml) to support other warehouses.
#}

with prep as (
  select
    * exclude (
      contexts_nl_basjes_yauaa_context_1,
      contexts_com_snowplowanalytics_snowplow_agent_classification_1,
      contexts_com_snowplowanalytics_snowplow_bot_detection_1,
      contexts_com_snowplowanalytics_snowplow_utm_referrer_1
    ),
    parse_json(ev.contexts_nl_basjes_yauaa_context_1) as contexts_nl_basjes_yauaa_context_1,
    parse_json(ev.contexts_com_snowplowanalytics_snowplow_agent_classification_1) as contexts_com_snowplowanalytics_snowplow_agent_classification_1,
    parse_json(ev.contexts_com_snowplowanalytics_snowplow_bot_detection_1) as contexts_com_snowplowanalytics_snowplow_bot_detection_1,
    parse_json(ev.contexts_com_snowplowanalytics_snowplow_utm_referrer_1) as contexts_com_snowplowanalytics_snowplow_utm_referrer_1

  from {{ ref('snowplow_agent_analytics_events') }} as ev
)

select
  *

from prep
