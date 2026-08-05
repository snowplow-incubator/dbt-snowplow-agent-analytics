{# Purpose from the agent classification enrichment context (com.snowplowanalytics.snowplow/agent_classification/1-0-0). #}
{% macro agent_purpose(table_alias) -%}
    {{ table_alias }}.contexts_com_snowplowanalytics_snowplow_agent_classification_1[0]:purpose::varchar
{%- endmacro %}
