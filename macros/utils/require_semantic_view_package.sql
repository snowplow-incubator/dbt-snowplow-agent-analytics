{# The `semantic_view` materialization comes from Snowflake-Labs/dbt_semantic_view,
   a documented prerequisite rather than a declared dependency: packages.yml is parsed
   as YAML before its Jinja is rendered, so a dependency cannot be made conditional.

   The var() test is required: dbt renders the body of disabled models at parse time,
   so checking package presence alone would fire for consumers who never opted in. #}
{% macro require_semantic_view_package() -%}
  {%- if var('enable_semantic_views', false) and dbt_semantic_view is not defined -%}
    {{ exceptions.raise_compiler_error(
        "enable_semantic_views is true, but the Snowflake-Labs/dbt_semantic_view package "
        ~ "is not installed. It supplies the `semantic_view` materialization. Add it to "
        ~ "your packages.yml and run `dbt deps`:\n\n"
        ~ "  - package: Snowflake-Labs/dbt_semantic_view\n"
        ~ "    version: [\">=1.0.6\", \"<2.0.0\"]\n\n"
        ~ "Or set enable_semantic_views to false to skip the semantic layer entirely."
    ) }}
  {%- endif -%}
{%- endmacro %}
