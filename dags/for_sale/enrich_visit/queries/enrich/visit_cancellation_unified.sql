WITH new_model AS (
  SELECT
    vsl.id_visit,
    vsl.id_schedule,
    vsl.id_author_user AS id_user,
    vsl.channel,
    vsl.on_behalf_of,
    vsl.reason,
    vsl.author_user_role,
    vsl.event_type AS type,
    IF(vsl.reason = 'REQUEST_EXPIRED', TRUE, FALSE) AS is_cancelled_by_expiration,
    vsl.ts_created,
    vsl.ts_updated
  FROM
    datalake_ebdb_clean.visit_status_log AS vsl
  JOIN
    datalake_ebdb_clean.visit AS v
      ON vsl.id_visit = v.id
  WHERE
    vsl.event_type IN ("VISIT_REQUEST_CANCELED", "VISIT_CANCELED")
    AND DATE(v.ts_created) >= '2024-11-01'
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY vsl.id_visit ORDER BY vsl.ts_created, vsl.id_visit_status_log DESC) = 1
),
old_model AS (
  WITH last_booking_status AS (
    SELECT
      b.id_visit,
      MAX_BY(b.id, b.ts_created) AS id_schedule,
      MAX_BY(bsc.id_user, struct(bsc.ts_created, bsc.id)) AS id_user,
      MAX_BY(b.status, b.ts_created) AS last_status,
      MAX(b.ts_updated) AS ts_created
    FROM
      datalake_ebdb_clean.booking AS b
    LEFT JOIN
      datalake_ebdb_clean.visit AS v
        ON b.id_visit = v.id
    LEFT JOIN
      datalake_ebdb_clean.booking_status_change AS bsc
        ON b.id = bsc.id_booking
    WHERE
      b.type = 'Visita'
      AND DATE(v.ts_created) < '2024-11-01'
    GROUP BY 1
  )
  SELECT
    lbs.id_visit,
    lbs.id_schedule,
    lbs.id_user,
    vcd.channel,
    vcd.on_behalf_of,
    vcd.reason,
    IF(vcd.reason = 'REQUEST_EXPIRED', TRUE, FALSE) AS is_cancelled_by_expiration,
    lbs.ts_created,
    lbs.ts_created AS ts_updated
  FROM
    last_booking_status AS lbs
  LEFT JOIN
    datalake_ebdb_clean.visit_cancellation_details AS vcd
      ON lbs.id_visit = vcd.id_visit
  WHERE
    lbs.last_status = 'Cancelado'
)
SELECT
  id_visit,
  id_schedule,
  id_user,
  channel,
  on_behalf_of,
  reason,
  author_user_role,
  type,
  is_cancelled_by_expiration,
  ts_created,
  ts_updated
FROM new_model
UNION ALL
SELECT
  id_visit,
  id_schedule,
  id_user,
  channel,
  on_behalf_of,
  reason,
  NULL AS author_user_role,
  NULL AS type,
  is_cancelled_by_expiration,
  ts_created,
  ts_updated
FROM old_model
