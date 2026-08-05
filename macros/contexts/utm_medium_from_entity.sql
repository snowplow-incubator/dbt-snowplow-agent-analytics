{# utm_medium from the utm_referrer entity (com.snowplowanalytics.snowplow/utm_referrer/1-0-0). #}
{% macro utm_medium_from_entity(table_alias) -%}
    {{ table_alias }}.contexts_com_snowplowanalytics_snowplow_utm_referrer_1[0]:medium::varchar
{%- endmacro %}
