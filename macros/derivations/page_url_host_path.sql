{# Page key: concat(page_urlhost, page_urlpath), robust to NULLs.
   A missing component contributes '', and a fully missing URL becomes 'unknown':
   the key must never be NULL because it is a merge upsert key in page_summary,
   and NULL never matches NULL in a merge, which would accumulate duplicate rows. #}
{% macro page_url_host_path(table_alias) -%}
    coalesce(
        nullif(
            concat(coalesce({{ table_alias }}.page_urlhost, ''), coalesce({{ table_alias }}.page_urlpath, '')),
            ''
        ),
        'unknown'
    )
{%- endmacro %}
