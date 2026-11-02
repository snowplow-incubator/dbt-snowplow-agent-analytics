{% macro check_warehouse() %}
  {% if target.type not in ['snowflake', 'bigquery', 'databricks'] %}
    {{ exceptions.raise_compiler_error(
      "Snowplow Error: snowplow_agent_analytics supports Snowflake, BigQuery, and Databricks. "
      ~ "The configured adapter is '" ~ target.type ~ "'. Use one of the supported adapters."
    ) }}
  {% endif %}
{% endmacro %}
