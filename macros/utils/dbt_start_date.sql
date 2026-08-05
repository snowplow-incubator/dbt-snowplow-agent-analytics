{# Earliest event date the daily tables consider. #}
{% macro dbt_start_date() -%}
    to_date('{{ var("dbt_start_date", "2024-01-01") }}')
{%- endmacro %}
