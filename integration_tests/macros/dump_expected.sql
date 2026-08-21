{# Print one of the *_actual models as CSV on stdout, for bootstrapping (or refreshing)
   the matching data/expected/*.csv seed.

   Usage, from the integration_tests directory, AFTER a full test run has built the models:

     dbt run-operation dump_expected --args '{model: page_summary_actual}' --quiet \
       > data/expected/page_summary_expected.csv

   --quiet suppresses dbt's own logging so only the CSV reaches stdout. Rows are ordered
   by every column so the output is byte-stable across runs and diffs cleanly in review.

   IMPORTANT: this captures whatever the models currently produce. Read the diff before
   committing it -- a bug in a model would otherwise be frozen into the expectation. #}

{%- macro _csv_cell(v) -%}
  {%- if v is none -%}
  {%- elif v is boolean -%}
    {{- 'true' if v else 'false' -}}
  {%- else -%}
    {%- set s = v | string -%}
    {%- if '"' in s or ',' in s or '\n' in s or '\r' in s -%}
      {{- '"' ~ s | replace('"', '""') ~ '"' -}}
    {%- else -%}
      {{- s -}}
    {%- endif -%}
  {%- endif -%}
{%- endmacro -%}


{% macro dump_expected(model) %}
  {%- if not execute -%}{{ return('') }}{%- endif -%}

  {%- set rel = ref(model) -%}
  {%- set cols = adapter.get_columns_in_relation(rel) | map(attribute='name') | list -%}
  {%- set col_list = cols | join(', ') -%}

  {%- set results = run_query('select ' ~ col_list ~ ' from ' ~ rel ~ ' order by ' ~ col_list) -%}

  {#- `do print(...)` rather than `{{ print(...) }}`: print returns None, which Jinja
      would render as the literal text "None" into the CSV. -#}
  {%- do print(cols | map('lower') | join(',')) -%}
  {%- for row in results.rows -%}
    {%- set cells = [] -%}
    {%- for v in row -%}
      {%- do cells.append(snowplow_agent_analytics_integration_tests._csv_cell(v)) -%}
    {%- endfor -%}
    {%- do print(cells | join(',')) -%}
  {%- endfor -%}
{% endmacro %}
