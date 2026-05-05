WITH new_model AS (
  SELECT
    vse.id_visit,
    vse.id_schedule,
    vse.id_author_user AS id_user,
    vse.channel,
    vse.channel_unified,
    vse.on_behalf_of,
    vse.reason,
    vse.author_user_role,
    vse.event_type AS type,
    IF(vse.reason = 'REQUEST_EXPIRED', TRUE, FALSE) AS is_cancelled_by_expiration,
    vse.ts_created,
    vse.ts_updated
  FROM
    datalake_visit.visit_status_events AS vse
  JOIN
    datalake_ebdb_clean.visit AS v
      ON vse.id_visit = v.id
  WHERE
    vse.event_type IN ("VISIT_REQUEST_CANCELED", "VISIT_CANCELED")
    AND DATE(v.ts_created) >= '2024-11-01'
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY vse.id_visit ORDER BY vse.ts_created, vse.id_visit_status_log DESC) = 1
),
old_model AS (
  WITH last_booking_status AS (
    SELECT
      b.id_visit,
      MAX(b.id) AS id_schedule,
      MAX_BY(bsc.id_user, struct(bsc.ts_created, bsc.id)) AS id_user,
      MAX_BY(b.status, struct(b.ts_created, b.id)) AS last_status,
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
  channel_unified,
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
  channel AS channel_unified,
  on_behalf_of,
  reason,
  NULL AS author_user_role,
  NULL AS type,
  is_cancelled_by_expiration,
  ts_created,
  ts_updated
FROM old_model
