WITH
new_model AS (
  SELECT
    id_visit,
    channel,
    on_behalf_of,
    reason,
    IF(reason = 'REQUEST_EXPIRED', TRUE, FALSE) AS is_cancelled_by_expiration,
    ts_created,
    ts_updated
  FROM
    datalake_ebdb_clean.visit_status_log
  WHERE
    event_type IN ("VISIT_REQUEST_CANCELED", "VISIT_CANCELED")
    AND DATE(ts_created) >= '2025-01-01'
),
old_model AS (
  SELECT
    id_visit,
    channel,
    on_behalf_of,
    reason,
    IF(reason = 'REQUEST_EXPIRED', TRUE, FALSE) AS is_cancelled_by_expiration,
    ts_created,
    ts_updated
  FROM
    datalake_ebdb_clean.visit_cancellation_details
  WHERE
    DATE(ts_created) < '2025-01-01'
)
SELECT
  id_visit,
  channel,
  on_behalf_of,
  reason,
  is_cancelled_by_expiration,
  ts_created,
  ts_updated
FROM new_model
UNION ALL
SELECT
  id_visit,
  channel,
  on_behalf_of,
  reason,
  is_cancelled_by_expiration,
  ts_created,
  ts_updated
FROM old_model
