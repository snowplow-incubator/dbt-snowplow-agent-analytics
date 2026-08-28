{# SQL membership test for an app_id list, e.g. "app_id in ('cdn', 'edge')".

   Single quotes in the values are escaped so a value like "o'reilly" cannot break the
   generated SQL. (Values containing '--' are still rejected by snowplow-utils' unsafe-SQL
   check on custom_filter.)

   Returns none for an empty list, leaving the caller to decide what "unset" means: no
   app_id restriction at all for client_app_ids, no CDN channel for cdn_app_ids. #}
{% macro app_id_filter(column, app_ids) -%}
    {%- if not app_ids -%}
        {{ return(none) }}
    {%- endif -%}
    {{ return(column ~ " in ('" ~ app_ids | map('replace', "'", "''") | join("', '") ~ "')") }}
{%- endmacro %}
