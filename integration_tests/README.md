# snowplow_agent_analytics integration tests

A standalone dbt project that installs the package from `../`, seeds a fixed event fixture in place of `atomic.events`, runs the full model chain over several incremental runs, and compares every output against a committed expected result.

## Layout

| Path | Purpose |
|------|---------|
| `data/source/snowplow_agent_analytics_events.csv` | The event fixture. 1,476 rows, 133 atomic columns, seeded as scalars. |
| `data/expected/*.csv` | Committed expected results, generated from a reviewed run — see below. |
| `models/source/snowflake/..._events_stg.sql` | `parse_json`s the four entity columns back into `variant`. This is what the package reads. |
| `models/actual/*_actual.sql` | One per output model; float columns rounded. |
| `models/expected/*_expected_stg.sql` | Reads the expected seed, rounds identically. |
| `models/actual/actual_vs_expected.yml` | `dbt_utils.equal_rowcount` + `dbt_utils.equality` per model. |
| `.scripts/integration_tests.sh` | Seed, run 6×, test. |
| `.scripts/bootstrap_expected.sh` | Regenerate `data/expected/` from a built run. |
| `.scripts/verify_fixture.py` | Reimplements the marts in Python and prints the coverage the fixture is designed for. |

## Running

```bash
cd integration_tests
export DBT_PROFILES_DIR=$PWD/ci     # or add an `integration_tests` profile to ~/.dbt
export SNOWFLAKE_TEST_ACCOUNT=... SNOWFLAKE_TEST_USER=... SNOWFLAKE_TEST_PASSWORD=...
export SNOWFLAKE_TEST_ROLE=... SNOWFLAKE_TEST_DATABASE=... SNOWFLAKE_TEST_WAREHOUSE=...
export SCHEMA_SUFFIX=$USER

dbt deps
bash .scripts/integration_tests.sh -d snowflake
```

## Regenerating `data/expected/`

`data/expected/` is already populated, so a clean checkout runs green: `dbt deps`, then
`integration_tests.sh` seeds, runs and tests against the committed expectations with no
extra setup.

Regenerate only when a change to the package is *supposed* to move the output — a new
column, a corrected aggregate, a reworked model. Then:

```bash
bash .scripts/integration_tests.sh -d snowflake   # fails at `dbt test` -- that's the point
bash .scripts/bootstrap_expected.sh snowflake     # dumps *_actual -> data/expected/*.csv
git diff data/expected/                           # READ THIS
dbt seed --full-refresh && dbt test               # should now pass
```

Only the equality tests fail on the first run; everything upstream of `dbt test` succeeds,
which is all `bootstrap_expected.sh` needs. Run it against a full sequence — it freezes
whatever the models currently emit, so dumping mid-backfill bakes in a partial answer.

Read the diff every time. `bootstrap_expected.sh` cannot tell an intended change from a
regression, so an unreviewed diff turns a bug into the expected answer. Check that the rows
that moved are the ones your change should have moved, and that nothing else did.
`.scripts/verify_fixture.py` independently reimplements the marts in Python and prints the
aggregates it expects; use it as a second opinion when reviewing (it is an approximation,
not ground truth).

## Why the runs are repeated

`snowplow__backfill_limit_days` is 30 and the fixture's `load_tstamp` spans 100 days, so
the incremental manifest needs four runs to catch up.

## Determinism

`page_summary` and `operator_summary` derive their 7/30/90d windows from `as_of_date()`,
normally `date_trunc('week', current_date)` — so their output would change every week and
the expected seeds would rot. The project therefore pins `snowplow__as_of_date` to
`2026-08-17`, the Monday inside the fixture's window, which makes both summaries
reproducible indefinitely. `summary_snapshot_retention_weeks` is raised to a large value
because the retention post-hook compares `as_of_date` against the real `current_date` and
would otherwise prune the pinned snapshot once 26 weeks of wall-clock time have passed.

The daily tables need no pinning: they key on `event_date` from the fixture, and their
late-data window takes `least(current_date - 3, min(event_date in batch))`, which resolves
to the batch minimum for any run after the fixture's last day.

Two residual `current_date` dependencies are accepted rather than pinned:

- `tests/assert_no_double_counting.sql` and `tests/assert_cdn_event_fingerprint_populated.sql`
  scope themselves to a trailing window off `current_date`, so they pass vacuously once
  wall-clock time has moved past the fixture. They still catch regressions when the
  fixture is regenerated to a current anchor.
- `is_new_operator_7d` is relative to the pinned `as_of_date`, so it *is* deterministic.

## Inspecting the fixture

```bash
python3 .scripts/verify_fixture.py
```

Reads the committed fixture and prints what it is designed to exercise. Useful as a second
opinion when reviewing a `data/expected/` diff, and it needs nothing from `fixtures/`.

It ends with **coverage guards** and exits non-zero if the fixture stops exercising a path
that only fires on a specific temporal pattern — currently the never-flip-back branch of
`int_agent_source_lookup`, which in this fixture is hit by exactly one agent
(`QualifiedBot`: client in batch 1, CDN-only in batch 4). That coverage is a side effect of
how `prepare_dataset.py` distributes rows, so without the guard a fixture rebuild could
remove it silently and `tests/assert_lookup_never_flips_back.sql` would start passing
vacuously.

## A known unrealism in the fixture

The source export was built with two independent `SAMPLE()` queries — one over CDN events,
one over client events, at different rates. That destroyed the correspondence between the
two sides: in production every CDN row for a JS-executing agent has a client-side
counterpart, but in the fixture it usually does not.

Consequences, all harmless for testing but confusing if you don't know:

- **Per-agent CDN/client row ratios are meaningless.** Meta-Externalagent has 23 CDN rows
  and 3 client rows, so the lookup's "prefer client" rule counts 3 and discards 23. That
  cannot happen in production.
- **"Client-only" agents are an artifact.** Meta-Webindexer and SEBot-WA have zero CDN rows
  here purely because sampling dropped them — not evidence of a CDN capture gap.

None of this weakens the suite. The fixture is fixed, so output is deterministic and
internally consistent, and every code path is still exercised. Do **not** "fix" the ratios
to look realistic: it would churn every expected CSV for no test benefit. If you ever do
want realistic correspondence, take a contiguous time slice rather than a random sample —
CDN and client rows share no join key, so sampling cannot preserve it.
