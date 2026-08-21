{# Float columns are rounded before comparison so tiny representation differences in
   safe_divide() don't fail the equality test. The expected_stg model rounds identically. #}
{% set columns = adapter.get_columns_in_relation(ref('operator_summary')) %}

select
    {% for col in columns if col.name.lower() not in ['crawl_to_referral_ratio_30d'] %}{{ col.name }}, {% endfor %}

    round(cast(crawl_to_referral_ratio_30d as {{ dbt.type_numeric() }}), 6) as crawl_to_referral_ratio_30d

from {{ ref('operator_summary') }}
