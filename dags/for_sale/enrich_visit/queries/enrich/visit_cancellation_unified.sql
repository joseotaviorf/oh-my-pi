WITH
new_model AS (
  SELECT
    id_visit,
    channel,
    on_behalf_of,
    reason,
    ts_created,
    ts_updated
  FROM
    datalake_ebdb_clean.visit_status_log
  WHERE
    event_type IN ("VISIT_REQUEST_CANCELED", "VISIT_CANCELED")
),
old_model AS (
  SELECT
    id_visit,
    channel,
    on_behalf_of,
    reason,
    ts_created,
    ts_updated
  FROM
    datalake_ebdb_clean.visit_cancellation_details
)
SELECT
  COALESCE(new_model.id_visit, old_model.id_visit) AS id_visit,
  COALESCE(new_model.channel, old_model.channel) AS channel,
  COALESCE(new_model.on_behalf_of, old_model.on_behalf_of) AS on_behalf_of,
  COALESCE(new_model.reason, old_model.reason) AS reason,
  COALESCE(new_model.ts_created, old_model.ts_created) AS ts_created,
  COALESCE(new_model.ts_updated, old_model.ts_updated) AS ts_updated
FROM
  new_model
FULL OUTER JOIN
  old_model
    ON new_model.id_visit = old_model.id_visit
