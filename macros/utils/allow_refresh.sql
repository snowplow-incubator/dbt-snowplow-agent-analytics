{# `full_refresh` config for the models that accumulate history: false where an
   accidental --full-refresh would drop it, none where refresh is allowed (dev target,
   or snowplow__allow_refresh) so the flag still works on the runs that ask for it.

   Never true, and never conditioned on flags.FULL_REFRESH: dbt evaluates config() once
   at parse time and caches it, so "the flag is set right now" would stick and every
   later run would rebuild from scratch. #}
{% macro allow_refresh() %}
    {{ return(adapter.dispatch('allow_refresh', 'snowplow_agent_analytics')()) }}
{% endmacro %}

{% macro default__allow_refresh() %}

    {% set allowed = snowplow_utils.get_value_by_target(
                        dev_value=true,
                        default_value=var('snowplow__allow_refresh', false),
                        dev_target_name=var('snowplow__dev_target_name', 'dev')
                        ) %}

    {{ return(none if allowed else false) }}

{% endmacro %}
