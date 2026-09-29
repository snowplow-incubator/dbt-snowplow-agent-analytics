{% docs __snowplow_agent_analytics__ %}

{% raw %}

# Snowplow Agent Analytics Package

Welcome to the model documentation site for the Snowplow agent analytics dbt package. The package
turns raw Snowplow atomic events into analytics-ready tables for AI agent traffic analysis: which
agents crawl your site, which pages they care about, and whether the operators behind them send
human pageviews back.

**For a quickstart guide, configuration and a walkthrough of the models, visit the
[Snowplow Docs](https://docs.snowplow.io/docs/modeling-your-data/modeling-your-data-with-dbt/dbt-quickstart/agent-analytics/).**

*Note this doc site is built from the `main` branch. If you are running a different version of the
package, [generate and serve](https://docs.getdbt.com/reference/commands/cmd-docs#dbt-docs-serve)
the doc site locally for accurate documentation.*

## Tables

| Table | Grain | Purpose |
|-------|-------|---------|
| `base_events` | one row per deduplicated event | Durable base table. Single scan of raw events; all downstream models read from here. |
| `int_agent_source_lookup` | `agent_name` | Per-agent JS-capability lookup. Determines whether to count an agent from CDN or client events. |
| `agent_pageviews_daily` | `event_date × agent_name × operator × purpose × source_channel × page_url_host_path` | Bot fact table. Source of truth for arbitrary slicing. |
| `human_pageviews_daily` | `event_date × page_url_host_path` | Human fact table. Pre-aggregated human page views. |
| `human_referrals_daily` | `event_date × referring_operator × page_url_host_path` | AI-referred human page views, broken out by operator. |
| `page_summary` | `page_url_host_path × as_of_date` | Page-centric scorecard: "how is this URL doing with AI?" |
| `operator_summary` | `operator × as_of_date` | Operator-centric scorecard: "are they crawling more than they refer?" |

## Overview

Raw `atomic.events` is scanned exactly once per run, driven by the snowplow-utils incremental
manifest:

- `base_new_event_limits` computes the run's `load_tstamp` bounds from the manifest.
- `base_events_this_run` reads only the new rows, keeps CDN events (`app_id` in `cdn_app_ids`) and
  client page views, deduplicates them, tags each row with `is_bot` and its source channel, and
  resolves `agent_name` / `agent_operator` / `agent_purpose`.
- `base_events` receives the batch. Everything downstream reads from it or from its daily
  descendants.
- `int_agent_source_lookup` assigns each agent one source channel — `client` once it has ever been
  seen client-side, `cdn` otherwise — so agents that run JS are never double-counted.
- The daily fact tables aggregate by `event_date`, and the summary tables snapshot 7/30/90-day
  windows per page and per operator.

The `on-run-end` hook advances the manifest only for models that succeeded, so a downstream failure
causes automatic reprocessing on the next run rather than silent data loss.

## Installation

Follow the [quickstart guide](https://docs.snowplow.io/docs/modeling-your-data/modeling-your-data-with-dbt/dbt-quickstart/agent-analytics/)
to install and configure the package.

{% endraw %}

{% enddocs %}
