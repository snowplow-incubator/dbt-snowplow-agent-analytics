{% macro prune_snapshots() -%}
  delete from {{ this }}
  where as_of_date < cast({{ dbt.dateadd('day', -7 * (var('summary_snapshot_retention_weeks', 26) | int), 'current_date') }} as date)
{%- endmacro %}
