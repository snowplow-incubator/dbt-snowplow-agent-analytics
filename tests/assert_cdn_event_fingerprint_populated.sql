-- Warn when recent CDN events carry a NULL event_fingerprint: the event
-- fingerprint enrichment is not enabled and CDN dedup falls back to event_id,
-- which is less reliable for edge-collected events.
{{ config(severity='warn') }}

select event_id, app_id, load_tstamp
from {{ ref('base_events') }}
where raw_source_channel = 'cdn'
  and event_fingerprint is null
  and load_tstamp >= dateadd(day, -7, current_timestamp)
