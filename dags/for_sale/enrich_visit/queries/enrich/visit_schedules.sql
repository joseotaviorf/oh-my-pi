WITH schedule AS (
  WITH new AS (
    SELECT
      vse.id_visit,
      vse.id_schedule,
      MAX(
        CASE
          WHEN vse.event_type IN ('VISIT_REQUESTED', 'VISIT_RESCHEDULED') THEN vse.id_author_user
        END
      ) AS id_user_creator,
      MAX(
        CASE
          WHEN vse.event_type IN ('VISIT_REQUESTED', 'VISIT_RESCHEDULED') THEN vse.author_user_role
        END
      ) AS user_role_creator,
      MAX(
        CASE
          WHEN vse.event_type IN ('VISIT_REQUESTED', 'VISIT_RESCHEDULED') THEN vse.channel
        END
      ) AS channel_creation,
      MAX(
        CASE
          WHEN vse.event_type IN ('VISIT_REQUESTED', 'VISIT_RESCHEDULED') THEN vse.channel_unified
        END
      ) AS channel_creation_unified,
      MAX(
        CASE
          WHEN vse.event_type IN ('VISIT_REQUESTED', 'VISIT_RESCHEDULED') THEN vse.application_source
        END
      ) AS application_source_creation,
      MAX(
        CASE
          WHEN vse.on_behalf_of = 'TENANT_LIVING' THEN vse.ts_created
        END
      ) AS ts_event_tenant,
      MIN(
        CASE
          WHEN vse.event_type IN ('VISIT_REQUESTED', 'VISIT_RESCHEDULED') THEN vse.ts_created
        END
      ) AS ts_schedule_created,
      MIN(
        CASE
          WHEN vse.event_type = 'VISIT_REQUESTED' THEN vse.ts_created
        END
      ) AS ts_schedule_requested,
      MIN(
        CASE
          WHEN vse.event_type = 'VISIT_RESCHEDULED' THEN vse.ts_created
        END
      ) AS ts_schedule_rescheduled,
      MIN(
        CASE
          WHEN vse.event_type = 'VISIT_CONFIRMED' THEN vse.ts_created
        END
      ) AS ts_schedule_confirmed,
      CASE
        WHEN MIN(vse.ts_created) FILTER (WHERE vse.event_type = 'VISIT_RESCHEDULED') IS NOT NULL THEN 'RESCHEDULE'
        ELSE 'REQUEST'
      END AS schedule_origin,
      MIN_BY(vse.channel, vse.ts_created) FILTER (WHERE vse.event_type = 'VISIT_CONFIRMED') AS first_confirmed_channel,
      MIN_BY(vse.channel_unified, vse.ts_created) FILTER (WHERE vse.event_type = 'VISIT_CONFIRMED') AS first_confirmed_channel_unified,
      MIN_BY(vse.author_user_role, vse.ts_created) FILTER (WHERE vse.event_type = 'VISIT_CONFIRMED') AS first_confirmed_user_role,
      MAX_BY(vse.event_type, vse.ts_created) FILTER (WHERE vse.event_type IN ('ANSWER_CONFIRMED', 'ANSWER_PENDING', 'ANSWER_REJECTED') AND vse.on_behalf_of = 'SUPPLY') AS last_confirm_answer_supply,
      MAX_BY(vse.event_type, vse.ts_created) FILTER (WHERE vse.event_type IN ('ANSWER_CONFIRMED', 'ANSWER_PENDING', 'ANSWER_REJECTED') AND vse.on_behalf_of = 'DEMAND') AS last_confirm_answer_demand,
      MAX_BY(vse.event_type, vse.ts_created) FILTER (WHERE vse.event_type IN ('ANSWER_CONFIRMED', 'ANSWER_PENDING', 'ANSWER_REJECTED') AND vse.on_behalf_of = 'AGENT') AS last_confirm_answer_agent,
      MAX_BY(vse.event_type, vse.ts_created) FILTER (WHERE vse.event_type IN ('ANSWER_CONFIRMED', 'ANSWER_PENDING', 'ANSWER_REJECTED') AND vse.on_behalf_of = 'TENANT_LIVING') AS last_confirm_answer_tenant_living,
      MAX_BY(vse.channel, vse.ts_created) FILTER (WHERE vse.event_type = 'ANSWER_CONFIRMED' AND vse.on_behalf_of = 'SUPPLY') AS channel_confirmed_supply,
      MAX_BY(vse.channel, vse.ts_created) FILTER (WHERE vse.event_type = 'ANSWER_CONFIRMED' AND vse.on_behalf_of = 'DEMAND') AS channel_confirmed_demand,
      MAX_BY(vse.channel, vse.ts_created) FILTER (WHERE vse.event_type = 'ANSWER_CONFIRMED' AND vse.on_behalf_of = 'AGENT') AS channel_confirmed_agent,
      MAX_BY(vse.channel, vse.ts_created) FILTER (WHERE vse.event_type = 'ANSWER_CONFIRMED' AND vse.on_behalf_of = 'TENANT_LIVING') AS channel_confirmed_tenant_living,
      MAX_BY(vse.channel_unified, vse.ts_created) FILTER (WHERE vse.event_type = 'ANSWER_CONFIRMED' AND vse.on_behalf_of = 'SUPPLY') AS channel_confirmed_supply_unified,
      MAX_BY(vse.channel_unified, vse.ts_created) FILTER (WHERE vse.event_type = 'ANSWER_CONFIRMED' AND vse.on_behalf_of = 'DEMAND') AS channel_confirmed_demand_unified,
      MAX_BY(vse.channel_unified, vse.ts_created) FILTER (WHERE vse.event_type = 'ANSWER_CONFIRMED' AND vse.on_behalf_of = 'AGENT') AS channel_confirmed_agent_unified,
      MAX_BY(vse.channel_unified, vse.ts_created) FILTER (WHERE vse.event_type = 'ANSWER_CONFIRMED' AND vse.on_behalf_of = 'TENANT_LIVING') AS channel_confirmed_tenant_living_unified
    FROM
      datalake_visit.visit_status_events AS vse
    JOIN
      datalake_ebdb_clean.visit AS v
        ON vse.id_visit = v.id
    WHERE
      v.ts_created::DATE >= '2024-11-01'
    GROUP BY 1, 2
  ),
  old AS (
    SELECT
      b.id_visit,
      b.id AS id_schedule,
      MAX_BY(b.slot_day, struct(b.ts_created, b.id)) AS slot_schedule,
      MIN_BY(bsc.id_user, bsc.id) AS id_user_creator,
      LAG(b.id) OVER(PARTITION BY b.id_visit ORDER BY MIN(b.ts_created), b.id) AS id_last_schedule,
      MAX(b.dt_booking) AS dt_schedule_visit,
      MIN(b.ts_created) AS ts_schedule_created,
      MIN(bsc.ts_created) FILTER (WHERE bsc.status = 'Marcado') AS ts_schedule_confirmed
    FROM
      datalake_ebdb_clean.booking AS b
    JOIN
      datalake_ebdb_clean.visit AS v
        ON b.id_visit = v.id
    LEFT JOIN
      datalake_ebdb_clean.booking_status_change AS bsc
        ON bsc.id_booking = b.id
    WHERE
      b.type = 'Visita'
      AND v.ts_created::DATE < '2024-11-01'
    GROUP BY 1,2
  )
  SELECT
    id_visit,
    id_schedule,
    id_user_creator,
    'NEW' AS source_schedule,
    NULL AS slot_schedule,
    user_role_creator,
    first_confirmed_channel,
    first_confirmed_channel_unified,
    first_confirmed_user_role,
    channel_creation,
    channel_creation_unified,
    application_source_creation,
    NULL AS dt_schedule_visit,
    ts_event_tenant,
    ts_schedule_created,
    ts_schedule_requested,
    ts_schedule_rescheduled,
    ts_schedule_confirmed,
    schedule_origin,
    LEAD(id_schedule) OVER(PARTITION BY id_visit ORDER BY ts_schedule_created, id_schedule) AS id_succeed_schedule,
    LEAD(ts_schedule_created) OVER(PARTITION BY id_visit ORDER BY ts_schedule_created, id_schedule) AS ts_next_schedule_created,
    LEAD(ts_schedule_created,2) OVER(PARTITION BY id_visit ORDER BY ts_schedule_created, id_schedule) AS ts_next_2_schedule_created,
    last_confirm_answer_supply,
    last_confirm_answer_demand,
    last_confirm_answer_agent,
    last_confirm_answer_tenant_living,
    channel_confirmed_supply,
    channel_confirmed_demand,
    channel_confirmed_agent,
    channel_confirmed_tenant_living,
    channel_confirmed_supply_unified,
    channel_confirmed_demand_unified,
    channel_confirmed_agent_unified,
    channel_confirmed_tenant_living_unified
  FROM
    new
  UNION ALL
  SELECT
    id_visit,
    id_schedule,
    id_user_creator,
    'OLD' AS source_schedule,
    slot_schedule,
    NULL AS user_role_creator,
    NULL AS first_confirmed_channel,
    NULL AS first_confirmed_channel_unified,
    NULL AS first_confirmed_user_role,
    NULL AS channel_creation,
    NULL AS channel_creation_unified,
    NULL AS application_source_creation,
    dt_schedule_visit,
    NULL AS ts_event_tenant,
    ts_schedule_created,
    IF(id_last_schedule IS NULL, ts_schedule_created, NULL) AS ts_schedule_requested,
    IF(id_last_schedule IS NOT NULL, ts_schedule_created, NULL) AS ts_schedule_rescheduled,
    ts_schedule_confirmed,
    IF(id_last_schedule IS NULL, 'REQUEST', 'RESCHEDULE') AS schedule_origin,
    LEAD(id_schedule) OVER(PARTITION BY id_visit ORDER BY ts_schedule_created, id_schedule) AS id_succeed_schedule,
    LEAD(ts_schedule_created) OVER(PARTITION BY id_visit ORDER BY ts_schedule_created, id_schedule) AS ts_next_schedule_created,
    LEAD(ts_schedule_created,2) OVER(PARTITION BY id_visit ORDER BY ts_schedule_created, id_schedule) AS ts_next_2_schedule_created,
    NULL AS last_confirm_answer_supply,
    NULL AS last_confirm_answer_demand,
    NULL AS last_confirm_answer_agent,
    NULL AS last_confirm_answer_tenant_living,
    NULL AS channel_confirmed_supply,
    NULL AS channel_confirmed_demand,
    NULL AS channel_confirmed_agent,
    NULL AS channel_confirmed_tenant_living,
    NULL AS channel_confirmed_supply_unified,
    NULL AS channel_confirmed_demand_unified,
    NULL AS channel_confirmed_agent_unified,
    NULL AS channel_confirmed_tenant_living_unified
  FROM
    old
),
visit_aud AS (
  SELECT
    va.id_visit,
    va.id_agent AS id_user_agent,
    u.id_agent AS id_agent,
    va.ts_visit,
    ure.ts_revision AS ts_created
  FROM
    datalake_ebdb_clean.visit_aud AS va
  LEFT JOIN
    datalake_ebdb_user.user_revision_entity AS ure
      ON va.rev = ure.id
  LEFT JOIN
    datalake_ebdb_clean.user AS u
      ON va.id_agent = u.id
),
agent_schedule AS (
  SELECT
    s.id_schedule,
    MIN_BY(v.id_agent, v.ts_created) AS id_first_agent,
    MIN_BY(v.id_user_agent, v.ts_created) AS id_first_user_agent,
    MAX_BY(v.id_agent, v.ts_created) AS id_last_agent,
    MAX_BY(v.id_user_agent, v.ts_created) AS id_last_user_agent
  FROM
    schedule AS s
  LEFT JOIN
    visit_aud AS v
      ON v.id_visit = s.id_visit
      AND v.ts_created >= s.ts_schedule_created
      AND v.ts_created < COALESCE(IF(s.ts_schedule_created = s.ts_next_schedule_created, s.ts_next_2_schedule_created, s.ts_next_schedule_created), NOW())
  GROUP BY 1
),
schedule_enriched AS (
  SELECT
    schedule.id_visit,
    schedule.id_schedule,
    schedule.id_user_creator,
    schedule.user_role_creator,
    schedule.first_confirmed_channel,
    schedule.first_confirmed_channel_unified,
    schedule.first_confirmed_user_role,
    schedule.channel_creation,
    schedule.channel_creation_unified,
    schedule.application_source_creation,
    schedule.ts_event_tenant,
    schedule.ts_schedule_created,
    schedule.ts_next_schedule_created,
    schedule.ts_schedule_requested,
    schedule.ts_schedule_rescheduled,
    schedule.ts_schedule_confirmed,
    schedule.schedule_origin,
    schedule.id_succeed_schedule,
    schedule.last_confirm_answer_supply,
    schedule.last_confirm_answer_demand,
    schedule.last_confirm_answer_agent,
    schedule.last_confirm_answer_tenant_living,
    schedule.channel_confirmed_supply,
    schedule.channel_confirmed_demand,
    schedule.channel_confirmed_agent,
    schedule.channel_confirmed_tenant_living,
    schedule.channel_confirmed_supply_unified,
    schedule.channel_confirmed_demand_unified,
    schedule.channel_confirmed_agent_unified,
    schedule.channel_confirmed_tenant_living_unified,
    CASE
      WHEN schedule.source_schedule = 'NEW' THEN va.ts_visit
      WHEN schedule.source_schedule = 'OLD' THEN MAKE_TIMESTAMP(EXTRACT(YEAR FROM schedule.dt_schedule_visit), EXTRACT(MONTH FROM schedule.dt_schedule_visit), EXTRACT(DAY FROM schedule.dt_schedule_visit), (schedule.slot_schedule/4) + 11, (schedule.slot_schedule%4)*15, 0)
    END AS ts_schedule_visit
  FROM
    schedule
  LEFT JOIN
    visit_aud AS va
      ON va.id_visit = schedule.id_visit
      AND va.ts_created > schedule.ts_schedule_created
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY schedule.id_schedule ORDER BY va.ts_created) = 1
),
visit_model AS (
  SELECT
    vse.id_visit,
    CASE
      WHEN vse.event_type = 'VISIT_FITTED' THEN 'FITTED'
      WHEN vse.event_type = 'VISIT_REGISTERED' THEN 'REGISTERED'
    END AS visit_model
  FROM
    datalake_visit.visit_status_events AS vse
  WHERE
    vse.event_type IN ('VISIT_FITTED', 'VISIT_REGISTERED')
)
SELECT DISTINCT
  s.id_schedule,
  s.id_visit,
  v.id_visitor,
  h.id_user AS id_owner,
  v.id_house,
  s.id_user_creator AS id_user_creation,
  s.user_role_creator AS user_role_creation,
  vcu.id_user AS id_user_cancelation,
  agent.id_first_agent,
  agent.id_first_user_agent,
  agent.id_last_agent AS id_agent,
  agent.id_last_user_agent AS id_user_agent,
  vbm.sk_broker_supply,
  vbm.sk_broker_demand,
  vbm.id_company_supply,
  vbm.id_company_demand,
  vbm.is_3p_supply,
  vbm.is_3p_demand,
  vbm.is_3p_lead_gen,
  vbm.has_3p_access_control,
  s.id_succeed_schedule,
  CONCAT(v.id_visitor, '_', v.id_house) AS id_sale_flow,
  h.id_region,
  v.code AS visit_code,
  v.business_context,
  vbm.business_model,
  CASE
    WHEN vm.visit_model IS NULL THEN 'STANDARD'
    ELSE vm.visit_model
  END AS visit_model,
  s.schedule_origin,
  s.channel_creation,
  s.channel_creation_unified,
  s.application_source_creation,
  NULLIF(CONCAT_WS(' - ', s.channel_creation, s.application_source_creation),'') AS source_creation_unified,
  s.first_confirmed_channel,
  s.first_confirmed_channel_unified,
  s.first_confirmed_user_role,
  s.last_confirm_answer_supply,
  s.last_confirm_answer_demand,
  s.last_confirm_answer_agent,
  s.last_confirm_answer_tenant_living,
  s.channel_confirmed_supply,
  s.channel_confirmed_demand,
  s.channel_confirmed_agent,
  s.channel_confirmed_tenant_living,
  s.channel_confirmed_supply_unified,
  s.channel_confirmed_demand_unified,
  s.channel_confirmed_agent_unified,
  s.channel_confirmed_tenant_living_unified,
  CASE
    WHEN s.last_confirm_answer_supply = 'ANSWER_CONFIRMED' THEN TRUE
    WHEN s.last_confirm_answer_supply IN ('ANSWER_PENDING', 'ANSWER_REJECTED') THEN FALSE
    ELSE NULL
  END AS is_confirmed_by_supply,
  CASE
    WHEN s.last_confirm_answer_demand = 'ANSWER_CONFIRMED' THEN TRUE
    WHEN s.last_confirm_answer_demand IN ('ANSWER_PENDING', 'ANSWER_REJECTED') THEN FALSE
    ELSE NULL
  END AS is_confirmed_by_demand,
  CASE
    WHEN s.last_confirm_answer_agent = 'ANSWER_CONFIRMED' THEN TRUE
    WHEN s.last_confirm_answer_agent IN ('ANSWER_PENDING', 'ANSWER_REJECTED') THEN FALSE
    ELSE NULL
  END AS is_confirmed_by_agent,
  CASE
    WHEN s.last_confirm_answer_tenant_living = 'ANSWER_CONFIRMED' THEN TRUE
    WHEN s.last_confirm_answer_tenant_living IN ('ANSWER_PENDING', 'ANSWER_REJECTED') THEN FALSE
    ELSE NULL
  END AS is_confirmed_by_tenant_living,
  IF(s.ts_schedule_confirmed IS NOT NULL, TRUE, FALSE) AS is_confirmed,
  IF(pva.event_type = 'VISIT_DONE', TRUE, FALSE) AS is_completed,
  IF(pva.event_type = 'VISIT_UNSUCCESSFUL', TRUE, FALSE) AS is_unsuccessful,
  IF(vcu.ts_created IS NOT NULL, TRUE, FALSE) AS is_canceled,
  IF(s.ts_schedule_rescheduled IS NOT NULL, TRUE, FALSE) AS is_rescheduled,
  IF(v.behavior IN ('CONFIRMATION_TENANT_LIVING','CONFIRMATION_TENANT_LIVING_ASSURED','CONFIRMATION_TENANT_LIVING_REQUIRED'), TRUE, FALSE) AS has_tenant_living,
  DATEDIFF(v.dt_visit, vcu.ts_created) AS days_visit_cancelled_to_visit,
  DATEDIFF(v.dt_visit, ts_schedule_created) AS days_visit_booked_to_visit,
  DATEDIFF(vcu.ts_created, ts_schedule_created) AS days_visit_booked_to_cancelled,
  DATEDIFF(IF(pva.event_type = 'VISIT_DONE', pva.ts_post_visit_agent, NULL), ts_schedule_created) AS days_visit_booked_to_visit_completed,
  v.ts_visit,
  s.ts_schedule_created,
  s.ts_next_schedule_created,
  s.ts_schedule_requested,
  s.ts_schedule_rescheduled,
  s.ts_schedule_confirmed,
  IF(pva.event_type = 'VISIT_DONE', pva.ts_post_visit_agent, NULL) AS ts_schedule_completed,
  IF(pva.event_type = 'VISIT_UNSUCCESSFUL', pva.ts_post_visit_agent, NULL) AS ts_schedule_unsuccessful,
  vcu.ts_created AS ts_schedule_canceled,
  s.ts_schedule_visit,
  v_cin.ts_checkin AS ts_visit_checkin,
  NOW() AS ts_load
FROM
  schedule_enriched AS s
LEFT JOIN
  datalake_ebdb_clean.visit AS v
    ON s.id_visit = v.id
LEFT JOIN
  datalake_visit.visit_business_model AS vbm
    ON v.id = vbm.id_visit
LEFT JOIN
  datalake_ebdb_clean.house AS h
    ON v.id_house = h.id
LEFT JOIN
  visit_model AS vm
    ON s.id_visit = vm.id_visit
LEFT JOIN
  agent_schedule AS agent
    ON agent.id_schedule = s.id_schedule
LEFT JOIN
  datalake_ebdb_clean.visit_checkin AS v_cin
    ON v_cin.id_visit = s.id_visit
LEFT JOIN
  datalake_visit.post_visit_agent_unified AS pva
    ON s.id_schedule = pva.id_schedule
LEFT JOIN
  datalake_visit.visit_cancellation_unified AS vcu
    ON s.id_schedule = vcu.id_schedule
