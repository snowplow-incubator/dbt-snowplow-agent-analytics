{# Float columns are rounded before comparison so tiny representation differences in
   safe_divide() don't fail the equality test. The expected_stg model rounds identically. #}
{% set columns = adapter.get_columns_in_relation(ref('page_summary')) %}

select
    {% for col in columns if col.name.lower() not in ['cite_through_rate_proxy_30d'] %}{{ col.name }}, {% endfor %}

    round(cast(cite_through_rate_proxy_30d as {{ dbt.type_numeric() }}), 6) as cite_through_rate_proxy_30d

from {{ ref('page_summary') }}
