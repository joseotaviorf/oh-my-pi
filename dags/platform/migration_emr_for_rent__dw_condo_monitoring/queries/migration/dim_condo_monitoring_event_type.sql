WITH event_types AS (
  SELECT
    source,
    event_name,
    MIN(ts_event) AS ts_event
  FROM
    datalake_condo_monitoring.condo_monitoring_events
  GROUP BY ALL
)
SELECT
  ROW_NUMBER() OVER(ORDER BY ts_event) AS sk_event_type,
  source,
  event_name
FROM
  event_types
