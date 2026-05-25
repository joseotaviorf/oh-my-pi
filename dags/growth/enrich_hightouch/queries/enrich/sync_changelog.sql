WITH filtered_runs AS (
  SELECT
    id_sync,
    id_sync_run,
    ts_started,
    ts_finished,
    year,
    month,
    day
  FROM
    datalake_hightouch.sync_runs
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
  r.id_sync,
  r.id_sync_run,
  r.ts_started,
  r.ts_finished,
  r.year,
  r.month,
  r.day,
  c.row_id,
  c.op_type,
  c.status,
  c.failure_reason,
  SPLIT(c.failure_reason,':')[0] AS failure_type
FROM filtered_runs AS r
INNER JOIN hightouch_audit.sync_changelog AS c
  ON r.id_sync = c.sync_id
  AND r.id_sync_run = c.sync_run_id;
