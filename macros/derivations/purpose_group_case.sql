{# Derives purpose_group (AI / SEARCH / OTHER) from an agent_purpose expression.
   NULL purposes fall into OTHER. Vocabulary: agent classification enrichment purposes. #}
{% macro purpose_group_case(purpose_expr) -%}
    case
        when {{ purpose_expr }} in ('AI_TRAINING', 'AI_USER_FETCH', 'AI_SEARCH_INDEX') then 'AI'
        when {{ purpose_expr }} in ('SEARCH_INDEX') then 'SEARCH'
        else 'OTHER'
    end
{%- endmacro %}
