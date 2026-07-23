WITH overrides AS (
  SELECT
    so.id_override_alias AS id_override,
    so.id_schedule,
    EXPLODE(so.rotation_ids) AS id_rotation,
    so.id_responder,
    so.responder_type,
    FROM_UTC_TIMESTAMP(so.ts_started, 'America/Sao_Paulo') AS ts_started,
    FROM_UTC_TIMESTAMP(so.ts_ended, 'America/Sao_Paulo') AS ts_ended,
    so.dt_load,
    so.year,
    so.month,
    so.day
  FROM
    datalake_jira_ops_clean.schedules_override AS so
),
last_override AS (
  SELECT
    o.id_override,
    o.id_schedule,
    o.id_rotation,
    XXHASH64(
      o.id_schedule,
      o.id_rotation,
      o.ts_started,
      o.ts_ended
    ) AS id_period,
    o.id_responder,
    o.responder_type,
    ROW_NUMBER() OVER(
      PARTITION BY 
        o.id_schedule,
        o.id_rotation,
        o.ts_started,
        o.ts_ended
      ORDER BY o.dt_load DESC
    ) = 1 AS is_last_period_override,
    o.ts_started,
    o.ts_ended,
    o.dt_load,
    o.year,
    o.month,
    o.day
  FROM
    overrides AS o
)
SELECT
  o.id_override,
  o.id_schedule,
  o.id_rotation,
  o.id_period,
  o.id_responder,
  o.responder_type,
  ua.display_name AS responder_name,
  ua.email_address AS responder_email,
  o.is_last_period_override,
  o.ts_started,
  o.ts_ended,
  o.dt_load,
  o.year,
  o.month,
  o.day
FROM
  last_override AS o
LEFT JOIN
  datalake_jira_ops_clean.user_account AS ua
    ON ua.id_account = o.id_responder
WHERE
  o.dt_load BETWEEN DATE("{load_start_date}") AND DATE("{load_end_date}")