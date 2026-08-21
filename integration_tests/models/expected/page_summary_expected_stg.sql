{# Mirrors the rounding in page_summary_actual so the equality test compares like for like. #}
{% set columns = adapter.get_columns_in_relation(ref('page_summary_expected')) %}

select
    {% for col in columns if col.name.lower() not in ['cite_through_rate_proxy_30d'] %}{{ col.name }}, {% endfor %}

    round(cast(cite_through_rate_proxy_30d as {{ dbt.type_numeric() }}), 6) as cite_through_rate_proxy_30d

from {{ ref('page_summary_expected') }}
