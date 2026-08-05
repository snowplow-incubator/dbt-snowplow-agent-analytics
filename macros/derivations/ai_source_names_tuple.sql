{# Convenience macro: SQL tuple of AI referral source names, for ad-hoc filtering.
   Defaults mirror the operator_referral_sources seed; override with var('ai_source_names'). #}
{% macro ai_source_names_tuple() -%}
    {%- set names = var('ai_source_names', ['ChatGPT', 'Claude', 'Perplexity', 'Gemini', 'Copilot', 'Meta AI', 'Grok']) -%}
    ('{{ names | join("', '") }}')
{%- endmacro %}
