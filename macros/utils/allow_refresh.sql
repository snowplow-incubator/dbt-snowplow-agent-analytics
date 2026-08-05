{# Guards the incremental manifest against accidental --full-refresh.
   Refresh is allowed in dev (snowplow__dev_target_name) or when snowplow__allow_refresh is true. #}
{% macro allow_refresh() %}
    {{ return(adapter.dispatch('allow_refresh', 'snowplow_agent_analytics')()) }}
{% endmacro %}

{% macro default__allow_refresh() %}

    {% if flags.FULL_REFRESH == True %}
        {% set allow_refresh = snowplow_utils.get_value_by_target(
                                    dev_value=none,
                                    default_value=var('snowplow__allow_refresh', false),
                                    dev_target_name=var('snowplow__dev_target_name', 'dev')
                                    ) %}
    {% else %}
        {% set allow_refresh = none %}
    {% endif %}

    {{ return(allow_refresh) }}

{% endmacro %}
