{# Canonical agent identifier from the yauaa enrichment context (nl.basjes/yauaa_context/1-0-0). #}
{% macro agent_name(table_alias) -%}
    {{ snowplow_agent_analytics.entity_field(table_alias, 'nl_basjes_yauaa_context_1', 'agent_name', 'agentName', 'string') }}
{%- endmacro %}
