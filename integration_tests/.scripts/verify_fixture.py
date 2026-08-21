"""Simulate the dbt models over the reshaped CSV to check test coverage."""
import csv, json, re, collections, datetime as dt

import os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + "/"
CDN_APP_ID = "docs-cloudflare"
TODAY = dt.date(2026, 8, 18)
AS_OF = TODAY - dt.timedelta(days=TODAY.weekday())      # date_trunc('week', current_date)
csv.field_size_limit(1 << 30)

CTX_Y = "CONTEXTS_NL_BASJES_YAUAA_CONTEXT_1"
CTX_B = "CONTEXTS_COM_SNOWPLOWANALYTICS_SNOWPLOW_BOT_DETECTION_1"
CTX_U = "CONTEXTS_COM_SNOWPLOWANALYTICS_SNOWPLOW_UTM_REFERRER_1"
CTX_A = "CONTEXTS_COM_SNOWPLOWANALYTICS_SNOWPLOW_AGENT_CLASSIFICATION_1"

SEED = {}
for s in csv.DictReader(open(ROOT + "../seeds/operator_referral_sources.csv")):
    SEED[(s["source_value"].lower(), s["medium_value"].lower())] = s["operator"]

# agent identity repair, mirroring base_events_this_run
OVERRIDES = sorted(
    ((o["ua_pattern"], o["agent_name"], o["agent_operator"] or None, o["agent_purpose"] or None)
     for o in csv.DictReader(open(ROOT + "../seeds/agent_ua_overrides.csv"))),
    key=lambda x: (-len(x[0]), x[0]))
IGNORED = {i["agent_name"] for i in
           csv.DictReader(open(ROOT + "../seeds/agent_name_ignore_list.csv")) if i["agent_name"]}


def _ilike(ua, pat):
    # Build the regex character by character. re.escape() leaves '%' untouched in modern
    # Python, so escaping first and then replacing r'\%' silently matches nothing and every
    # override is skipped.
    rx = "".join(".*" if ch == "%" else "." if ch == "_" else re.escape(ch) for ch in pat)
    return re.fullmatch(rx, ua or "", re.I | re.S) is not None


def resolve_agent(ua, yauaa_name, op, purpose):
    """agent_name takes the override; operator/purpose only fill gaps."""
    for pat, name, o_op, o_pu in OVERRIDES:
        if _ilike(ua, pat):
            return name, (op or o_op), (purpose or o_pu)
    return yauaa_name, op, purpose


def c1(r, col, key):
    v = r[col]
    if not v:
        return None
    try:
        return json.loads(v)[0].get(key)
    except Exception:
        return None


# the seed header is lowercase; upper-case the keys so the checks below read like the
# atomic column names they mirror
rows = [{k.upper(): v for k, v in r.items()}
        for r in csv.DictReader(open(ROOT + "data/source/snowplow_agent_analytics_events.csv",
                                     newline="", encoding="utf-8"))]

# ---- base_events_this_run: dedup + tag
seen, base = set(), []
for r in rows:
    cdn = r["APP_ID"] == CDN_APP_ID
    k = ("cdn", r["EVENT_FINGERPRINT"] or r["EVENT_ID"]) if cdn else ("web", r["EVENT_ID"])
    if k in seen:
        continue
    seen.add(k)
    r = dict(r)
    r["_bot"] = c1(r, CTX_B, "bot")
    r["_chan"] = "cdn" if cdn else "client"
    r["_agent"], r["_op"], r["_purpose"] = resolve_agent(
        r["USERAGENT"], c1(r, CTX_Y, "agentName"),
        c1(r, CTX_A, "operator"), c1(r, CTX_A, "purpose"))
    r["_date"] = dt.date.fromisoformat(r["DERIVED_TSTAMP"][:10])
    r["_page"] = (r["PAGE_URLHOST"] or "") + (r["PAGE_URLPATH"] or "") or "unknown"
    base.append(r)
print(f"base_events: {len(base)} rows (deduped from {len(rows)})")

# ---- int_agent_source_lookup
chan = collections.defaultdict(set)
for r in base:
    if r["_bot"] and r["_agent"]:
        chan[r["_agent"]].add(r["_chan"])
# admitted only if bot-flagged in CDN at some point, and not ignore-listed
lookup = {a: ("client" if "client" in c else "cdn") for a, c in chan.items()
          if "cdn" in c and a not in IGNORED}
print(f"int_agent_source_lookup: {len(lookup)} agents "
      f"({sum(1 for v in lookup.values() if v=='client')} client / "
      f"{sum(1 for v in lookup.values() if v=='cdn')} cdn)")

# ---- int_agent_pageviews_unified -> agent_pageviews_daily
unified = [r for r in base if r["_bot"] and r["_agent"] in lookup
           and lookup[r["_agent"]] == r["_chan"]]
apd = collections.Counter()
for r in unified:
    apd[(r["_date"], r["_agent"], r["_op"], r["_purpose"], r["_page"])] += 1

# ---- human_pageviews_daily
hpd = collections.Counter()
for r in base:
    if r["_bot"] is False and r["_chan"] == "client":
        hpd[(r["_date"], r["_page"])] += 1

# ---- human_referrals_daily
hrd = collections.Counter()
hrd_sess = collections.defaultdict(set)
for r in base:
    if not (r["_bot"] is False and r["_chan"] == "client"):
        continue
    src = (c1(r, CTX_U, "source") or r["REFR_SOURCE"] or "").lower()
    med = (c1(r, CTX_U, "medium") or r["REFR_MEDIUM"] or "").lower()
    op = SEED.get((src, med))
    if op:
        hrd[(r["_date"], op, r["_page"])] += 1
        if r["DOMAIN_SESSIONID"]:
            hrd_sess[(r["_date"], op, r["_page"])].add(r["DOMAIN_SESSIONID"])

print(f"agent_pageviews_daily: {len(apd)} rows, {sum(apd.values())} hits")
print(f"human_pageviews_daily: {len(hpd)} rows, {sum(hpd.values())} pageviews")
print(f"human_referrals_daily: {len(hrd)} rows, {sum(hrd.values())} referred pageviews")

# ---- day coverage
print("\n=== day coverage in window ===")
SPAN = 100
days = [(TODAY - dt.timedelta(days=i)) for i in range(SPAN)]


def cov(name, dates):
    s = set(dates)
    inwin = [d for d in days if d in s]
    print(f"{name:28s} {len(inwin):3d}/100 days   range {min(s)} .. {max(s)}")


cov("agent_pageviews_daily", [k[0] for k in apd])
cov("human_pageviews_daily", [k[0] for k in hpd])
cov("human_referrals_daily", [k[0] for k in hrd])

print("\n=== rows/day evenness (in-window days) ===")
for nm, keys in (("agent hits", [(k[0], v) for k, v in apd.items()]),
                 ("human pageviews", [(k[0], v) for k, v in hpd.items()]),
                 ("referred pageviews", [(k[0], v) for k, v in hrd.items()])):
    per = collections.Counter()
    for d, v in keys:
        per[d] += v
    vals = [per[d] for d in days]
    print(f"  {nm:20s} mean {sum(vals)/len(vals):5.2f}  min {min(vals):3d}  max {max(vals):3d}  "
          f"zero-days {sum(1 for v in vals if v==0):3d}  last30 {sum(per[d] for d in days if AS_OF - dt.timedelta(days=30) <= d <= AS_OF):4d}")

# ---- page_summary
def win(d, n):
    return AS_OF - dt.timedelta(days=n) <= d <= AS_OF


pages = set(k[4] for k in apd) | set(k[1] for k in hpd)
summary = []
for p in pages:
    a30 = sum(v for k, v in apd.items() if k[4] == p and win(k[0], 30))
    a7 = sum(v for k, v in apd.items() if k[4] == p and win(k[0], 7))
    a90 = sum(v for k, v in apd.items() if k[4] == p and win(k[0], 90))
    h30 = sum(v for k, v in hpd.items() if k[1] == p and win(k[0], 30))
    h90 = sum(v for k, v in hpd.items() if k[1] == p and win(k[0], 90))
    r30 = sum(v for k, v in hrd.items() if k[2] == p and win(k[0], 30))
    fetch = sum(v for k, v in apd.items() if k[4] == p and win(k[0], 30)
                and k[3] in ("AI_USER_FETCH", "AI_SEARCH_INDEX"))
    summary.append(dict(page=p, a7=a7, a30=a30, a90=a90, h30=h30, h90=h90, r30=r30,
                        fetch=fetch, orphan=(a30 >= 10 and h30 < 5)))

print(f"\n=== page_summary ({len(summary)} pages) ===")
print(f"is_orphaned_agent_interest = TRUE : {sum(1 for s in summary if s['orphan'])}")
print(f"pages with agent_hits_30d >= 10   : {sum(1 for s in summary if s['a30']>=10)}")
print(f"pages with human_pageviews_30d>=5 : {sum(1 for s in summary if s['h30']>=5)}")
print(f"pages with ai_referral_pv_30d > 0 : {sum(1 for s in summary if s['r30']>0)}")
print(f"pages w/ cite_through denominator : {sum(1 for s in summary if s['fetch']>0)}")
print(f"pages w/ cite_through num AND den : {sum(1 for s in summary if s['fetch']>0 and s['r30']>0)}")
print(f"pages with zero agent hits (90d)  : {sum(1 for s in summary if s['a90']==0)}")
print(f"pages with zero humans (90d)      : {sum(1 for s in summary if s['h90']==0)}")

print("\ntop pages by agent_hits_30d:")
for s in sorted(summary, key=lambda x: -x["a30"])[:10]:
    print(f"  a7={s['a7']:3d} a30={s['a30']:3d} a90={s['a90']:3d} h30={s['h30']:3d} "
          f"r30={s['r30']:3d} orphan={str(s['orphan']):5s} {s['page'][:64]}")

# ---- operator_summary
ops = set(k[2] for k in apd if k[2]) | set(k[1] for k in hrd)
print(f"\n=== operator_summary ({len(ops)} operators) ===")
osum = []
for o in sorted(ops):
    c30 = sum(v for k, v in apd.items() if k[2] == o and win(k[0], 30))
    c90 = sum(v for k, v in apd.items() if k[2] == o and win(k[0], 90))
    p30 = sum(v for k, v in hrd.items() if k[1] == o and win(k[0], 30))
    s30 = len(set().union(*[hrd_sess[k] for k in hrd_sess if k[1] == o and win(k[0], 30)]) or set())
    osum.append((o, c30, c90, p30, s30))
print("  operator            crawl30 crawl90  refpv30 refsess30")
for o, c30, c90, p30, s30 in osum:
    print(f"  {o:20s} {c30:5d} {c90:6d}  {p30:6d} {s30:7d}")
print(f"\noperators with BOTH crawl and referral in 30d: "
      f"{sum(1 for o,c30,c90,p30,s30 in osum if c30>0 and p30>0)}")
print(f"crawl-only: {sum(1 for o,c30,c90,p30,s30 in osum if c30>0 and p30==0)}  "
      f"referral-only: {sum(1 for o,c30,c90,p30,s30 in osum if c30==0 and p30>0)}")

# ---- out-of-window rows (should exist, to prove the filters bite)
print(f"\nrows with event_date outside the 90d window: "
      f"{sum(1 for r in base if not win(r['_date'], 90))}")
print(f"  of those, before as_of-90: {sum(1 for r in base if r['_date'] < AS_OF - dt.timedelta(days=90))}")
print(f"  of those, after  as_of:   {sum(1 for r in base if r['_date'] > AS_OF)}")
print(f"as_of_date (weekly) = {AS_OF}; 90d window = "
      f"{AS_OF - dt.timedelta(days=90)} .. {AS_OF}")

# ---- load_tstamp spread (incremental batching)
lt = sorted(dt.date.fromisoformat(r["LOAD_TSTAMP"][:10]) for r in rows if r["LOAD_TSTAMP"])
print(f"\nload_tstamp span: {lt[0]} .. {lt[-1]} ({(lt[-1]-lt[0]).days+1} days, "
      f"{len(set(lt))} distinct days)")

# ---- coverage guards -------------------------------------------------------------
# These assert that the fixture still exercises paths that only fire on a specific
# temporal pattern. The coverage is a side effect of how prepare_dataset.py distributes
# rows, so a change to ANCHOR/SPAN or the resampling could silently remove it -- and
# tests/assert_lookup_never_flips_back.sql would then pass vacuously, which is worse
# than failing. Exit non-zero so a fixture rebuild cannot quietly lose them.
print("\n=== coverage guards ===")
failures = []

START = dt.date(2026, 5, 1)          # snowplow__start_date in integration_tests
BACKFILL = 30                        # snowplow__backfill_limit_days


def batch_of(r):
    return (dt.date.fromisoformat(r["LOAD_TSTAMP"][:10]) - START).days // BACKFILL + 1


chan_by_batch = collections.defaultdict(lambda: collections.defaultdict(set))
for r in base:
    if r["_bot"] and r["_agent"]:
        chan_by_batch[r["_agent"]][batch_of(r)].add(r["_chan"])

flip = []
for a, batches in chan_by_batch.items():
    client_seen = False
    for b in sorted(batches):
        chans = batches[b]
        if "client" in chans:
            client_seen = True
        elif client_seen and chans == {"cdn"}:
            flip.append(a)
            break

lifetime = {a: set().union(*b.values()) for a, b in chan_by_batch.items()}
n_dual = sum(1 for v in lifetime.values() if v == {"cdn", "client"})
n_cdn = sum(1 for v in lifetime.values() if v == {"cdn"})
n_cli = sum(1 for v in lifetime.values() if v == {"client"})

n_orphan = sum(1 for x in summary if x["orphan"])
n_cite = sum(1 for x in summary if x["fetch"] > 0 and x["r30"] > 0)
n_no_agent = sum(1 for x in summary if x["a90"] == 0)
n_7d = sum(1 for x in summary if x["a7"] > 0)
ops_both = sum(1 for o, c30, c90, p30, s30 in osum if c30 > 0 and p30 > 0)
ops_ref_only = sum(1 for o, c30, c90, p30, s30 in osum if c30 == 0 and p30 > 0)

checks = [
    ("never-flip-back path exercised", len(flip) >= 1, f"agents: {sorted(flip)}"),
    # mart thresholds: these silently stop firing if agent volume or the page weighting
    # in prepare_dataset.py changes, leaving the branch untested rather than failing
    ("is_orphaned_agent_interest fires", n_orphan >= 1, f"{n_orphan} pages"),
    ("cite_through has num and den", n_cite >= 1, f"{n_cite} pages"),
    ("pages with no agent interest", n_no_agent >= 1, f"{n_no_agent} pages"),
    ("7d agent window non-empty", n_7d >= 1, f"{n_7d} pages"),
    ("operators that crawl and refer", ops_both >= 1, f"{ops_both} operators"),
    ("referral-only operators", ops_ref_only >= 1, f"{ops_ref_only} operators"),
    ("dual-channel agents present", n_dual >= 1, f"{n_dual} agents"),
    ("cdn-only agents present", n_cdn >= 1, f"{n_cdn} agents"),
    ("client-only agents present", n_cli >= 1, f"{n_cli} agents"),
]
for name, ok, detail in checks:
    print(f"  {'PASS' if ok else 'FAIL'}  {name:34s} {detail}")
    if not ok:
        failures.append(name)

if failures:
    print(f"\n{len(failures)} coverage guard(s) failed -- the fixture no longer exercises "
          f"these paths, so the matching tests would pass vacuously.")
    raise SystemExit(1)
print("\nall coverage guards passed")
