# snowplow_agent_analytics

A dbt package that turns raw Snowplow atomic events into analytics-ready tables for AI agent
traffic analysis: which agents crawl your site, which pages they care about, and whether the
operators behind them send human pageviews back.

| Table | Grain | Purpose |
|-------|-------|---------|
| `base_events` | one row per deduplicated event | Durable base table. Single scan of raw events; all downstream models read from here. |
| `int_agent_source_lookup` | `agent_name` | Per-agent JS-capability lookup. Determines whether to count an agent from CDN or client events. |
| `agent_pageviews_daily` | `event_date × agent_name × operator × purpose × source_channel × page_url_host_path` | Bot fact table. Source of truth for arbitrary slicing. |
| `human_pageviews_daily` | `event_date × page_url_host_path` | Human fact table. Pre-aggregated human page views. |
| `human_referrals_daily` | `event_date × referring_operator × page_url_host_path` | AI-referred human page views, broken out by operator. |
| `page_summary` | `page_url_host_path × as_of_date` | Page-centric scorecard: "how is this URL doing with AI?" |
| `operator_summary` | `operator × as_of_date` | Operator-centric scorecard: "are they crawling more than they refer?" |

Model and column docs are published as a dbt docs site on GitHub Pages, rebuilt from the
integration test fixture on every push to `main` (`.github/workflows/publish-gh-pages.yml`).

## Requirements

- **Warehouse:** Snowflake (v1 supports Snowflake only)
- **dbt:** >= 1.10.6
- **Packages:** [snowplow-utils](https://github.com/snowplow/dbt-snowplow-utils) >= 1.0.1 (incremental manifest), dbt-utils
- **Optional:** [Snowflake-Labs/dbt_semantic_view](https://github.com/Snowflake-Labs/dbt_semantic_view) >= 1.0.6 — only if you set `enable_semantic_views`; add it to your own `packages.yml`, see [Semantic views](#semantic-views-snowflake-opt-in)
- **Snowplow enrichments:**
  - [Bot detection](https://docs.snowplow.io/) (`bot_detection/1-0-0`) — row-level bot/human split
  - [YAUAA](https://docs.snowplow.io/) (`yauaa_context/1-0-0`) — canonical `agentName`
  - Agent classification (`agent_classification/1-0-0`) — `operator`, `purpose`
  - `utm_referrer/1-0-0` entity — UTM-based referral attribution (falls back to `refr_*` fields)
  - [Event fingerprint](https://docs.snowplow.io/docs/pipeline/enrichments/available-enrichments/event-fingerprint-enrichment/) — strongly recommended for CDN-side dedup; without it CDN dedup falls back to `event_id` and `assert_cdn_event_fingerprint_populated` warns

## Architecture

Raw `atomic.events` is scanned **exactly once per run**:

1. `base_new_event_limits` computes the run's `load_tstamp` bounds from the **incremental manifest**
   (snowplow-utils `_t` macro family, same pattern as
   [dbt-snowplow-identities](https://github.com/snowplow-incubator/dbt-snowplow-identities)).
2. `base_events_this_run` (scratch, rebuilt each run) reads only the new rows, keeps CDN events
   (`app_id in var('cdn_app_ids')`, every request is a "hit") and client page views
   (`platform = 'web' and event_name = 'page_view'`, narrowed to `var('client_app_ids')`
   when that list is non-empty), deduplicates
   (client: `event_id`; CDN: `coalesce(event_fingerprint, event_id)`), and tags rows with
   `is_bot` and `raw_source_channel`. It also resolves `agent_name` / `agent_operator` /
   `agent_purpose` (see [Agent identity](#agent-identity)).
3. `base_events` (durable, idempotent `delete+insert` keyed on `event_id`) receives the batch.
   Everything downstream reads from it or from its pre-aggregated daily descendants. Note the
   spec's `insert_overwrite` is not used because on Snowflake it truncates the whole table rather
   than replacing partitions; `delete+insert` (on `event_id` here, on `event_date` in the daily
   tables) implements the intended partition-overwrite semantics.
4. The `on-run-end` hook advances the manifest **only for models that succeeded**, so a downstream
   failure causes automatic reprocessing on the next run rather than silent data loss.

Agents that run JS fire events in both subsets. `int_agent_source_lookup` assigns each agent one
source channel — `client` once it has ever been seen client-side (better fidelity for SPAs), and
that assignment never flips back — and `int_agent_pageviews_unified` applies it so no agent is
double-counted.

## Agent identity

`agent_name` is the join key for the whole agent side of the package, and yauaa's
`agentName` alone is not a safe one. yauaa reports a browser-masquerading crawler as the
browser it imitates: a request sent as

```
Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) \
  Chrome/145.0.0.0 Safari/537.36 (compatible; meta-externalagent/1.1; +https://...)
```

arrives with `agentName = 'Chrome'`. The `agent_classification` enrichment reads yauaa, so
those rows also come through with a NULL `operator` and `purpose` — nothing downstream can
recover the identity on its own. Two seeds handle this:

| Seed | Purpose |
|------|---------|
| `agent_ua_overrides` | Repairs `agent_name` (and fills `operator` / `purpose`) by matching `useragent` with `ILIKE`. Add a row per misattributed crawler. |
| `agent_name_ignore_list` | `agent_name` values too generic to identify anything. Excluded from `int_agent_source_lookup`, so they never reach the agent marts. |

The ignore list is the failsafe for the override seed being incomplete: a masquerading UA
with no override still gets bot-flagged on the CDN side, which would mark `Chrome` as a
CDN-seen agent — and that one row would then pull every client-side datacenter-IP Chrome
event into the agent marts under the same name.

`int_agent_source_lookup` admits an agent only if it was **bot-flagged in CDN** at some
point. CDN-side detection has only the user agent string available, so a CDN bot flag is
evidence the agent is identifiable; an agent flagged solely client-side was caught by
`asnLookups` or `clientSideDetection` (datacenter IP ranges, automation markers) and has no
reliable identity.

Overrides are a workaround for a gap in the yauaa rules, so it is worth reporting
misattributed crawlers upstream as well — the enrichment is where this really belongs. The
seed fills `operator` / `purpose` only when the enrichment left them NULL, so it becomes a
no-op by itself once the enrichment handles the agent.

## Configuration

Set under `vars: snowplow_agent_analytics:` in your project:

| Var | Default | Description |
|-----|---------|-------------|
| `snowplow__atomic_schema` | `atomic` | Schema holding the Snowplow events table |
| `snowplow__events_table` | `events` | Events table name |
| `snowplow__database` | `target.database` | Database holding the events table |
| `cdn_app_ids` | `['cdn']` | `app_id` values identifying CDN/edge events |
| `client_app_ids` | `[]` (all) | `app_id` values to restrict client-side events to. Empty means every `app_id`; set it when the pipeline carries client-side trackers for other properties you do not want in this package. |
| `snowplow__start_date` | `2024-01-01` | Earliest date to process on first run |
| `snowplow__backfill_limit_days` | `30` | Max days processed per run during backfill |
| `snowplow__allow_refresh` | `false` | Allow `--full-refresh` to drop the incremental manifest |
| `late_data_window_days` | `3` | Minimum trailing days rebuilt by the daily tables each run. The rebuild window automatically extends to cover the oldest event date in the current manifest batch, so backfills and failure replays reach the daily tables too. |
| `dbt_start_date` | `2024-01-01` | Earliest event date in the daily tables |
| `summary_snapshot_mode` | `weekly` | `latest` (rebuild, current date only) \| `weekly` (snapshot per Monday) \| `daily` |
| `summary_snapshot_retention_weeks` | `26` | Snapshot retention for the summary tables |
| `enable_semantic_views` | `false` | Build the conformed dimensions and the Snowflake semantic view. See [Semantic views](#semantic-views-snowflake-opt-in). |
| `snowplow__as_of_date` | unset | Pins the summary snapshot date (`YYYY-MM-DD`), overriding `summary_snapshot_mode`. Set it to make the 7/30/90d windows reproducible — a backfill or replay wants them anchored to the date being rebuilt rather than to whenever the run executes. Used by the integration tests. |
| `orphan_agent_hits_threshold` | `10` | Agent hits (30d) above which a page can be flagged orphaned |
| `orphan_human_pageviews_threshold` | `5` | Human pageviews (30d) below which a page can be flagged orphaned |

The `operator_referral_sources` seed maps operators to referral `source`/`medium` values
(`utm_referrer` entity preferred, `refr_source`/`refr_medium` fallback). Override it with your
site's UTM conventions; `operator` values must match the agent classification enrichment exactly.

`assert_no_orphan_operators` warns when an AI-purpose operator crawls the site but is missing
from that seed, since its referrals then cannot be attributed. Some operators run crawlers and
no product that sends readers back — Amazon and Common Crawl, for instance — so there is nothing
to map; list those in `operators_without_referrals` to exempt them from the warning.

## Running

```bash
dbt deps
dbt seed
dbt run
dbt test
```

Models tracked by the incremental manifest are tagged `snowplow_agent_analytics_incremental`. To replay
a model from scratch, remove it from the manifest:
`dbt run --vars '{models_to_remove: [agent_pageviews_daily]}'`.

`--full-refresh` is guarded for the models whose state cannot be rebuilt from a single batch
(`incremental_manifest`, `base_events`, `int_agent_source_lookup`): it only takes effect on the
dev target or with `snowplow__allow_refresh: true`.

## Exemplar queries

Top N agents visiting the site (optionally by purpose):

```sql
select agent_name, agent_operator, sum(hits) as hits
from agent_pageviews_daily
where event_date >= current_date - 30
  -- and purpose_group = 'AI'
group by 1, 2
order by hits desc
limit 20;
```

Top N pages visited by agents (per operator or purpose):

```sql
select page_url_host_path, sum(hits) as hits
from agent_pageviews_daily
where event_date >= current_date - 30
  and agent_operator = 'OpenAI'
group by 1
order by hits desc
limit 20;
```

Agent mix over time (WoW by operator):

```sql
select date_trunc('week', event_date) as week, agent_operator, sum(hits) as hits
from agent_pageviews_daily
group by 1, 2
order by 1, hits desc;
```

New agent detection (first seen in the last 7 days):

```sql
select agent_name, agent_operator, min(event_date) as first_seen_date
from agent_pageviews_daily
group by 1, 2
having min(event_date) >= current_date - 7;
```

Per-page AEO scorecard and orphaned agent interest:

```sql
select *
from page_summary
where as_of_date = (select max(as_of_date) from page_summary)
  and is_orphaned_agent_interest
order by agent_hits_30d desc;
```

Per-operator crawl-vs-referral ratio:

```sql
select agent_operator, crawl_hits_30d, referred_sessions_30d, crawl_to_referral_ratio_30d
from operator_summary
where as_of_date = (select max(as_of_date) from operator_summary)
order by crawl_to_referral_ratio_30d desc nulls first;
```

## Semantic views (Snowflake, opt-in)

Set `enable_semantic_views: true` to also build `agent_analytics_semantic_view`, a
[Snowflake semantic view](https://docs.snowflake.com/en/sql-reference/sql/create-semantic-view)
over the three daily fact tables, so Cortex Analyst (or any other natural-language consumer) can
query the package without a hand-written prompt per question.

```bash
dbt deps
dbt run --vars '{enable_semantic_views: true}'
```

```sql
select * from semantic_view(
  snowplow_agent_analytics.agent_analytics_semantic_view
  METRICS total_agent_hits, total_referred_sessions, crawl_to_referral_ratio
  DIMENSIONS operator
) order by crawl_to_referral_ratio desc nulls last;
```

The daily facts only — `page_summary` and `operator_summary` are rollups of the same data, so a
second view over them would add no answers while forcing the agent to pick between two sources
that disagree on what "the last 30 days" means.

`AI_SQL_GENERATION` instructions on the view carry the caveats that would otherwise be lost:
agent hits and human pageviews come from different collection channels and are not a like-for-like
funnel; summing `referred_sessions` across days double-counts sessions spanning midnight;
`source_channel` is a diagnostic, not a traffic split.

### Prerequisite

dbt has no native semantic view materialization ([dbt-adapters#1260](https://github.com/dbt-labs/dbt-adapters/issues/1260)).
The `semantic_view` materialization comes from
[`Snowflake-Labs/dbt_semantic_view`](https://github.com/Snowflake-Labs/dbt_semantic_view), which
this package does **not** declare in `packages.yml`. If you opt in, add it to yours:

```yaml
packages:
  - package: Snowflake-Labs/dbt_semantic_view
    version: [">=1.0.6", "<2.0.0"]
```

dbt parses `packages.yml` as YAML before rendering its Jinja, so a dependency cannot be made
conditional — declaring it would make every consumer install it for a feature that is off by
default, and break `dbt deps` for anyone already depending on it at an incompatible range.
Forgetting it fails at parse time with an actionable message, not a materialization-not-found
error at run time.

`create_or_alter: true` is worth knowing about: it issues `CREATE OR ALTER SEMANTIC VIEW` instead
of `CREATE OR REPLACE`, preserving grants and materializations when only the body changes.

### Structure

```
agent_pageviews_daily ─┬─> dim_date ────┐
human_pageviews_daily ─┼─> dim_page ────┼─> agent_analytics_semantic_view
human_referrals_daily ─┴─> dim_operator ┘
```

The conformed dimensions are required, not decoration. `RELATIONSHIPS` only expresses many-to-one
joins, so relating the fact tables to each other directly means nominating one as the "one" side —
which drops rows (an operator that refers but never crawls becomes unreachable) and over-counts
the other side, whose row repeats for every row it matches. A shared dimension gives all three
tables the same grouping key and lets each metric aggregate within its own table before the join.

`dim_date`, `dim_page` and `dim_operator` are portable SQL. The semantic view is gated on
`target.type == 'snowflake'` in its `config()`, so on any other warehouse it is excluded at parse
time rather than failing at run time.

## Known limitations

- If an agent runs JS on some page templates but not others (e.g. an agentic browser hitting a
  JSON API endpoint), those API hits are dropped once `source_channel = 'client'`. Accepted for v1.
- Two genuinely distinct CDN requests with byte-identical payloads collapse to one row under
  fingerprint dedup. Additionally, the snowplow-utils batch macro dedupes on `event_id` before
  the fingerprint pass, so CDN synthetic duplicates (same `event_id`, different fingerprint)
  also collapse to one row — CDN hit counts are a conservative lower bound.
- Summary windows end at `as_of_date` (inclusive). In weekly mode that is the Monday of the
  current week, so data from Tuesday onwards appears in the following week's snapshot.
- Summing `referred_sessions` across days over-counts sessions spanning multiple days; the
  summary-table session windows are an upper bound on true uniques.
- `cite_through_rate_proxy_30d` is a proxy, not real attribution.
