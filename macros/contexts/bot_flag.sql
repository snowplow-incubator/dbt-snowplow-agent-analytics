{# Bot flag from the bot detection enrichment context (com.snowplowanalytics.snowplow/bot_detection/1-0-0).
   NULL when the enrichment did not attach a context; such rows are excluded from both
   the agent (is_bot = true) and human (is_bot = false) subsets downstream. #}
{% macro bot_flag(table_alias) -%}
    {{ table_alias }}.contexts_com_snowplowanalytics_snowplow_bot_detection_1[0]:bot::boolean
{%- endmacro %}
