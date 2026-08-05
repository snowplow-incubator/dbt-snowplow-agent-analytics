{# Snapshot date for the summary tables.
   weekly  -> Monday of the current week (one snapshot per week; mid-week runs refresh it,
              but the summaries only include event_date <= as_of_date, so the row is
              stable once Monday's data has finished loading)
   latest / daily -> current_date #}
{% macro as_of_date() -%}
    {%- if var('summary_snapshot_mode', 'weekly') == 'weekly' -%}
        date_trunc('week', current_date)
    {%- else -%}
        current_date
    {%- endif -%}
{%- endmacro %}
