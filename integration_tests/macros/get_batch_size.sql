{# Overrides dbt's built-in seed batch size (root-project macros win over the global
   project). The fixture is 133 columns wide and averages ~1.9 KB per row, so dbt's
   default batching would emit an INSERT of roughly 1.04 MB -- right at Snowflake's 1 MB
   maximum statement size, before SQL quoting overhead is even counted. 100 rows keeps
   each statement around 0.22 MB.

   dbt-snowplow-media-player carries the same override for the same reason. #}
{% macro get_batch_size() %}
  {{ return(100) }}
{% endmacro %}
