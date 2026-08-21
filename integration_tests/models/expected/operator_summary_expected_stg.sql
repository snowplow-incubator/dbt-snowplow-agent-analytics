{# Mirrors the rounding in operator_summary_actual so the equality test compares like for like. #}
{% set columns = adapter.get_columns_in_relation(ref('operator_summary_expected')) %}

select
    {% for col in columns if col.name.lower() not in ['crawl_to_referral_ratio_30d'] %}{{ col.name }}, {% endfor %}

    round(cast(crawl_to_referral_ratio_30d as {{ dbt.type_numeric() }}), 6) as crawl_to_referral_ratio_30d

from {{ ref('operator_summary_expected') }}
