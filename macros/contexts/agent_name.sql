{# Canonical agent identifier from the yauaa enrichment context (nl.basjes/yauaa_context/1-0-0). #}
{% macro agent_name(table_alias) -%}
    {{ table_alias }}.contexts_nl_basjes_yauaa_context_1[0]:agentName::varchar
{%- endmacro %}
