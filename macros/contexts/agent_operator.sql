{# Operator from the agent classification enrichment context (com.snowplowanalytics.snowplow/agent_classification/1-0-0). #}
{% macro agent_operator(table_alias) -%}
    {{ snowplow_agent_analytics.entity_field(table_alias, 'com_snowplowanalytics_snowplow_agent_classification_1', 'operator', 'operator', 'string') }}
{%- endmacro %}
