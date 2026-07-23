WITH schedules_base_timeline AS (
  SELECT
    id_schedule,
    rotation.id AS id_rotation,
    rotation.name AS rotation_name,
    rotation.order AS rotation_order,
    period.type AS period_type,
    period.responder.id AS id_responder,
    period.responder.type AS responder_type,
    COALESCE(period.responder.deleted, FALSE) AS is_responder_deleted,
    rotation.deleted AS is_rotation_deleted,
    period.startDate AS ts_period_started,
    period.endDate AS ts_period_ended,
    dt_load,
    ts_started,
    ts_ended,
    year,
    month,
    day
  FROM
    datalake_jira_ops_clean.schedules_timeline
  LATERAL VIEW EXPLODE(base_timeline.rotations) r AS rotation
  LATERAL VIEW EXPLODE(rotation.periods) p AS period
  WHERE
    dt_load BETWEEN DATE("{load_start_date}") AND DATE("{load_end_date}")
),
schedules_final_timeline AS (
  SELECT
    id_schedule,
    rotation.id AS id_rotation,
    rotation.name AS rotation_name,
    rotation.order AS rotation_order,
    period.type AS period_type,
    period.responder.id AS id_responder,
    period.responder.type AS responder_type,
    COALESCE(period.responder.deleted, FALSE) AS is_responder_deleted,
    flattened_responder.id AS id_flattened_responder,
    flattened_responder.type AS flattened_responder_type,
    rotation.deleted AS is_rotation_deleted,
    period.startDate AS ts_period_started,
    period.endDate AS ts_period_ended,
    dt_load,
    ts_started,
    ts_ended,
    year,
    month,
    day
  FROM
    datalake_jira_ops_clean.schedules_timeline
  LATERAL VIEW EXPLODE(final_timeline.rotations) r AS rotation
  LATERAL VIEW EXPLODE(rotation.periods) p AS period
  LATERAL VIEW EXPLODE(period.flattenedResponders) p AS flattened_responder
  WHERE
    dt_load BETWEEN DATE("{load_start_date}") AND DATE("{load_end_date}")
),
union_timelines AS (
  SELECT
    sbt.id_schedule,
    sbt.id_rotation,
    "base" AS timeline_version,
    sbt.rotation_name,
    sbt.rotation_order,
    sbt.period_type,
    sbt.id_responder,
    sbt.responder_type,
    NULL AS id_flattened_responder,
    NULL AS flattened_responder_type,
    sbt.is_responder_deleted,
    sbt.is_rotation_deleted,
    sbt.dt_load,
    sbt.ts_period_started,
    sbt.ts_period_ended,
    sbt.ts_started,
    sbt.ts_ended,
    sbt.year,
    sbt.month,
    sbt.day
  FROM
    schedules_base_timeline AS sbt
  UNION ALL
  SELECT
    sft.id_schedule,
    sft.id_rotation,
    "final" AS timeline_version,
    sft.rotation_name,
    sft.rotation_order,
    sft.period_type,
    sft.id_responder,
    sft.responder_type,
    sft.id_flattened_responder,
    sft.flattened_responder_type,
    sft.is_responder_deleted,
    sft.is_rotation_deleted,
    sft.dt_load,
    sft.ts_period_started,
    sft.ts_period_ended,
    sft.ts_started,
    sft.ts_ended,
    sft.year,
    sft.month,
    sft.day
  FROM
    schedules_final_timeline AS sft
)
SELECT
  s.id_schedule,
  s.id_team,
  ut.id_rotation,
  XXHASH64(
    s.id_schedule, 
    ut.id_rotation, 
    ut.ts_period_started, 
    ut.ts_period_ended
  ) AS id_period,
  ut.id_responder,
  ut.id_flattened_responder,
  s.name AS schedule_name,
  ut.timeline_version,
  ut.rotation_name,
  ut.rotation_order,
  ut.period_type,
  ua.display_name AS responder_name,
  ua.email_address AS responder_email,
  ut.is_responder_deleted,
  ut.is_rotation_deleted,
  FROM_UTC_TIMESTAMP(ut.ts_period_started, 'America/Sao_Paulo') AS ts_period_started,
  FROM_UTC_TIMESTAMP(ut.ts_period_ended, 'America/Sao_Paulo') AS ts_period_ended,
  FROM_UTC_TIMESTAMP(ut.ts_started, 'America/Sao_Paulo') AS ts_timeline_started,
  FROM_UTC_TIMESTAMP(ut.ts_ended, 'America/Sao_Paulo') AS ts_timeline_ended,
  ut.dt_load,
  ut.year,
  ut.month,
  ut.day
FROM
  union_timelines AS ut
JOIN
  datalake_jira_ops_clean.schedules AS s
    ON s.id_schedule = ut.id_schedule
LEFT JOIN
  datalake_jira_ops_clean.user_account AS ua
    ON ua.id_account = ut.id_responder