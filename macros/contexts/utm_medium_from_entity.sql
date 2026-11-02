{# utm_medium from the utm_referrer entity (com.snowplowanalytics.snowplow/utm_referrer/1-0-0). #}
{% macro utm_medium_from_entity(table_alias) -%}
    {{ snowplow_agent_analytics.entity_field(table_alias, 'com_snowplowanalytics_snowplow_utm_referrer_1', 'medium', 'medium', 'string') }}
{%- endmacro %}
