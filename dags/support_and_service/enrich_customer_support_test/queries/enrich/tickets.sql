WITH weekends_and_holidays AS (
  SELECT
    ad.date AS dt_non_working
  FROM
    datalake_quintoandar.aux_date AS ad
  WHERE
    ad.weekend = 'Weekend'
  UNION
  SELECT
    sch.dt_holiday AS dt_non_working
  FROM
    datalake_gsheets_clean.service_city_holidays AS sch
  WHERE
    sch.category = 'Nacional'
),
incoming_tickets AS (
  SELECT
    id_ticket,
    id_problem_ticket,
    id_user_main,
    id_contract,
    id_call,
    id_session,
    group_name AS ticket_queue,
    contact_ticket,
    task_sid_twilio,
    COALESCE(
      task_sid_twilio,
      NULLIF(REGEXP_EXTRACT(contact_ticket, '(WT[a-z0-9]{{20,40}})'), ''),
      NULLIF(REGEXP_EXTRACT(description, '(WT[a-z0-9]{{20,40}})'), '')
    ) AS twilio_task,
    tags,
    description,
    status,
    analyst_email,
    channel,
    request_type,
    client_type,
    step_tag,
    customer_type_tag,
    contact_theme_tag,
    contact_motivation_tag,
    contact_theme_detail_tag,
    custom_fields AS custom_fields_map,
    TO_JSON(custom_fields) AS custom_fields,
    reopens,
    replies,
    CAST(dt_budgeted AS TIMESTAMP) AS ts_budget,
    ts_created - INTERVAL 3 HOUR AS ts_created,
    ts_solved - INTERVAL 3 HOUR AS ts_solved,
    ts_closed - INTERVAL 3 HOUR AS ts_closed,
    ts_updated - INTERVAL 3 HOUR AS ts_updated,
    year,
    month,
    day
  FROM
    datalake_zendesk.tickets_current AS t
  WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
),
/* The following CTE is needed because a single call/chat can create multiple tickets. Also, there are
two CTEs for call dedupping because sometimes the id_call on a ticket is actually an id_task */
unique_twilio_tickets AS (
  SELECT
    it.id_session,
    'chat' AS channel,
    MAX(it.id_ticket) AS id_ticket
  FROM
    incoming_tickets AS it
  INNER JOIN
    datalake_customer_support_test.chats AS ch
      ON ch.id_session = it.id_session
  GROUP BY 1, 2
  UNION ALL
  SELECT
    it.id_call,
    'call' AS channel,
    MAX(it.id_ticket) AS id_ticket
  FROM
    incoming_tickets AS it
  INNER JOIN -- TODO: this OR yields poor performance but is needed as it.id_call is ambiguous
    datalake_customer_support_test.calls AS ca
      ON ca.id_call = it.id_call
      OR ca.id_task = it.id_call
  GROUP BY 1, 2
),
unique_tickets AS (
  SELECT
    id_ticket,
    channel
  FROM
    unique_twilio_tickets
  UNION ALL
  SELECT DISTINCT
    it.id_ticket,
    CASE
      WHEN it.channel IN ('email', 'form_faq', 'web', 'other')
        AND it.tags NOT LIKE '%resolve_ticket_acompanhamento%'
        AND it.tags NOT LIKE '%fechado_automaticamente_noreply%'
        AND it.tags NOT LIKE '%redirecionado_atendimento_2%'
        AND it.tags NOT LIKE '%closed_by_merge%'
        AND it.tags NOT LIKE '%zapdesk%'
        AND it.tags NOT LIKE '%ticket_via_call%'
        AND it.tags NOT LIKE '%call_contato_receptivo%'
        AND it.tags NOT LIKE '%call_contato_ativo%'
        AND it.tags NOT LIKE '%redirecionado_adm_v1%'
        AND it.id_call IS NULL
        AND it.id_session IS NULL THEN 'email'
      ELSE it.channel
    END AS channel
  FROM
    incoming_tickets AS it
  LEFT JOIN
    unique_twilio_tickets AS dtt
      ON dtt.id_ticket = it.id_ticket
  WHERE
    dtt.id_ticket IS NULL
),
tickets_per_task AS (
  SELECT
    dt.id_ticket,
    t.id_problem_ticket,
    t.id_user_main,
    t.id_contract,
    t.id_call,
    t.id_session,
    COALESCE(ch.queue_name, ca.queue_name, t.ticket_queue) AS queue,
    t.contact_ticket,
    t.task_sid_twilio,
    t.twilio_task,
    t.tags,
    t.description,
    t.status,
    ch.source,
    CASE
      WHEN ca.direction IN ('outbound-api', 'outbound') OR ca.channel_type = 'call-in-app' THEN 'OUTBOUND'
      WHEN ca.direction = 'inbound' THEN 'INBOUND'
      WHEN t.tags LIKE '%"ticket_ativo"%' THEN 'OUTBOUND'
      ELSE 'INBOUND'
    END AS direction,
    dt.channel,
    t.request_type,
    t.client_type,
    t.step_tag,
    t.customer_type_tag,
    t.contact_theme_tag,
    t.contact_motivation_tag,
    t.contact_theme_detail_tag,
    t.custom_fields_map,
    t.custom_fields,
    t.reopens,
    t.replies,
    ca.is_call_answered,
    t.ts_budget,
    t.ts_created,
    t.ts_solved,
    t.ts_closed,
    t.ts_updated,
    t.year,
    t.month,
    t.day
  FROM
    incoming_tickets AS t
  INNER JOIN
    unique_tickets AS dt
      ON dt.id_ticket = t.id_ticket
  LEFT JOIN
    datalake_customer_support_test.chats AS ch
      ON ch.id_task = t.twilio_task
  LEFT JOIN
    datalake_customer_support_test.calls AS ca
      ON COALESCE(ca.id_call, ca.id_task) = t.id_call
),
ticket_queue_attributes AS (
  WITH queue_metrics AS (
    SELECT
      id_ticket,
      FIRST(queue) OVER (PARTITION BY id_ticket ORDER BY ts_created) AS first_queue,
      LAST(queue) OVER (PARTITION BY id_ticket ORDER BY ts_created) AS last_queue,
      FIRST(analyst_email) OVER (PARTITION BY id_ticket ORDER BY ts_created) AS first_analyst_email,
      LAST(analyst_email) OVER (PARTITION BY id_ticket ORDER BY ts_created) AS last_analyst_email
    FROM
      tickets_per_task
  )
  SELECT
    tq.id_ticket,
    tq.first_queue,
    tq.last_queue,
    tq.first_analyst_email,
    tq.last_analyst_email,
    dc.front_or_back,
    dc.journey_step,
    dc.team,
    dc.area
  FROM
    queue_metrics AS tq
  LEFT JOIN
    datalake_gsheets_clean.department_control dc
      ON dc.department = tq.last_queue
),
tickets AS (
  SELECT DISTINCT
    t.id_ticket,
    t.id_problem_ticket,
    t.id_user_main,
    t.id_contract,
    t.id_call,
    t.id_session,
    tq.first_queue,
    tq.last_queue,
    tq.first_analyst_email,
    tq.last_analyst_email,
    t.contact_ticket,
    t.task_sid_twilio,
    t.twilio_task,
    t.tags,
    t.description,
    CASE
      WHEN LOWER(tq.front_or_back) = 'back'
        AND t.tags NOT LIKE '%bot_end_conversation%'
        AND t.tags NOT LIKE '%closed_by_merge%'
        AND (
          t.tags LIKE '%tarefa_atendimento_escalado%'
          OR LOWER(tq.front_or_back) = 'back'
        ) THEN TRUE
      ELSE FALSE
    END AS is_back_ticket,
    tq.front_or_back,
    tq.journey_step,
    tq.team,
    tq.area,
    t.status,
    t.channel,
    t.request_type,
    t.client_type,
    t.step_tag,
    t.customer_type_tag,
    t.contact_theme_tag,
    t.contact_motivation_tag,
    t.contact_theme_detail_tag,
    t.custom_fields,
    t.reopens,
    t.replies,
    t.is_call_answered,
    t.ts_budget,
    t.ts_created,
    t.ts_solved,
    t.ts_closed,
    t.ts_updated,
    t.year,
    t.month,
    t.day
  FROM
    tickets_per_task AS t
  INNER JOIN
    ticket_queue_attributes AS tq
      ON tq.id_ticket = t.id_ticket
),
back_tickets AS (
  SELECT
    bt.id_ticket AS id_back_ticket,
    bt.status,
    COALESCE(
      ft_chat.id_ticket,
      ft_call.id_ticket,
      NULLIF(REGEXP_EXTRACT(bt.contact_ticket, '^#?([0-9]{{8}})', 1), ''),
        REGEXP_EXTRACT(
          SUBSTRING(SPLIT(REGEXP_REPLACE(bt.description, 'WT[a-z0-9]{{20,40}}',''), 'Ticket do contato')[1], 1, 18),
          '([0-9]{{8}})',
          1
        )
    ) AS id_front_ticket,
    bt.ts_created,
    bt.ts_solved
  FROM
    tickets AS bt
  LEFT JOIN
    tickets AS ft_chat
      ON ft_chat.id_session = bt.id_session
      AND ft_chat.is_back_ticket IS FALSE
  LEFT JOIN
    tickets AS ft_call
      ON ft_call.task_sid_twilio = bt.task_sid_twilio
      AND ft_call.is_back_ticket IS FALSE
  WHERE
    bt.is_back_ticket IS TRUE
),
back_ticket_timestamps AS (
  SELECT
    id_front_ticket,
    ARRAY_AGG(id_back_ticket) AS back_ticket_list,
    SUM(
      CAST(status IN ('closed', 'deleted', 'solved') AS SMALLINT)
    ) - COUNT(DISTINCT(id_back_ticket)) != 0 AS has_open_back_ticket,
    CAST((TO_UNIX_TIMESTAMP(MIN(ts_created)) - TO_UNIX_TIMESTAMP(MAX(ts_solved))) / 60.0 AS DOUBLE) AS total_backoffice_minutes_time
  FROM
    back_tickets
  GROUP BY 1
),
/*
TODO: the following 'sla' CTEs are a replica of the ones in datalake_customer_demand.base_tasks and should be
revisited, ideally performing array operations on the date columns instead of JOINing on the result of
EXPLODE(SEQUENCE())
*/
unique_theme_detail_sla_target AS (
  SELECT DISTINCT
    journey_step,
    contact_theme_detail_tag AS taxonomy_tag,
    sla_in_days,
    EXPLODE(SEQUENCE(dt_start, COALESCE(dt_end, DATE(NOW())))) AS dt_reference
  FROM
    datalake_gsheets_clean.taxonomy_sla
  WHERE
    dt_target_invalidated IS NULL
),
unique_theme_sla_target AS (
  WITH exploded_theme_sla AS (
    SELECT
      journey_step,
      contact_theme_tag AS taxonomy_tag,
      sla_in_days,
      EXPLODE(SEQUENCE(dt_start, COALESCE(dt_end, DATE(NOW())))) AS dt_reference
    FROM
      datalake_gsheets_clean.taxonomy_sla
    WHERE
      dt_target_invalidated IS NULL
  )
  SELECT
    journey_step,
    taxonomy_tag,
    MIN(sla_in_days) AS sla_in_days,
    dt_reference
  FROM
    exploded_theme_sla
  GROUP BY 1,2,4
),
unique_journey_sla_target AS (
  WITH exploded_journey_taxonomy AS (
    SELECT
      journey_step,
      sla_in_days,
      EXPLODE(SEQUENCE(dt_start, COALESCE(dt_end, DATE(NOW())))) AS dt_reference
    FROM
      datalake_gsheets_clean.taxonomy_sla
    WHERE
      dt_target_invalidated IS NULL
  )
  SELECT
    journey_step,
    MIN(sla_in_days) AS sla_in_days,
    dt_reference
  FROM
    exploded_journey_taxonomy
  GROUP BY 1,3
),
ticket_sla_target AS (
  SELECT /*+ RANGE_JOIN(t, 500) */
    t.id_ticket,
    MIN(
      CASE
        WHEN t.last_queue IN ('Proteção QuintoAndar [OFF] [POS] [BACK]', 'Rescisão - Despejo [OFF][POS][BACK]') THEN 21
        ELSE COALESCE(tst.sla, tds.sla_in_days, ts.sla_in_days, ujst.sla_in_days)
      END
    ) AS sla_target,
    MAX(
      CASE
        WHEN t.ts_budget IS NOT NULL
          AND t.ts_budget >= ts_created - INTERVAL 3 HOUR
          AND t.ts_budget < COALESCE(ts_solved, NOW()) THEN t.ts_budget
        ELSE t.ts_created
      END
    ) AS ts_sla_started,
    ts_solved
  FROM
    tickets AS t
  LEFT JOIN
    datalake_gsheets_clean.tag_sla_target AS tst
      ON t.journey_step = tst.journey
      AND t.tags LIKE CONCAT('%', tst.tag, '%')
      AND t.ts_created BETWEEN tst.dt_start AND COALESCE(tst.dt_end, NOW())
  LEFT JOIN
    unique_theme_detail_sla_target AS tds
      ON t.journey_step = tds.journey_step
      AND t.contact_theme_detail_tag = tds.taxonomy_tag
      AND DATE(t.ts_created) = tds.dt_reference
  LEFT JOIN
    unique_theme_sla_target AS ts
      ON t.journey_step = ts.journey_step
      AND t.contact_theme_tag = ts.taxonomy_tag
      AND DATE(t.ts_created) = ts.dt_reference
  LEFT JOIN
    unique_journey_sla_target AS ujst
      ON t.journey_step = ujst.journey_step
      AND DATE(t.ts_created) = ujst.dt_reference
  WHERE
    t.tags NOT LIKE '%robotserviceaccount02%'
    AND (
      (
        t.last_queue = 'Offboarding Reparos [OFF] [POS] [BACK]'
        AND t.tags LIKE '%orçamentação_realizada%'
      )
      OR t.last_queue != 'Offboarding Reparos [OFF] [POS] [BACK]'
    )
  GROUP BY ALL
),
ticket_date_interval AS (
  SELECT
    id_ticket,
    sla_target,
    SEQUENCE(DATE(ts_sla_started), COALESCE(DATE(ts_solved), CURRENT_DATE())) AS dt_interval,
    ts_sla_started,
    ts_solved
  FROM
    ticket_sla_target
),
ticket_days_off AS (
  SELECT
    id_ticket,
    sla_target,
    ARRAY_SIZE(ARRAY_INTERSECT(dt_interval, (SELECT ARRAY_AGG(dt_non_working) FROM weekends_and_holidays))) AS days_off,
    ts_sla_started,
    ts_solved
  FROM
    ticket_date_interval
),
ticket_days_worked AS (
  SELECT
    id_ticket,
    sla_target,
    days_off,
    DATEDIFF(DATE(ts_solved), DATE(ts_sla_started)) - COALESCE(days_off, 0) AS days_worked,
    ts_sla_started
  FROM
    ticket_days_off
)
SELECT DISTINCT
  t.id_ticket,
  t.id_problem_ticket,
  t.id_user_main,
  t.id_contract,
  t.id_call,
  t.id_session,
  t.first_queue,
  t.last_queue,
  t.first_analyst_email,
  t.last_analyst_email,
  t.front_or_back,
  t.journey_step,
  t.team,
  t.area,
  t.status,
  t.channel,
  t.tags,
  t.description,
  t.request_type,
  t.client_type,
  t.step_tag,
  t.customer_type_tag,
  t.contact_theme_tag,
  t.contact_motivation_tag,
  t.contact_theme_detail_tag,
  t.custom_fields,
  t.reopens,
  t.replies,
  btt.back_ticket_list,
  btt.total_backoffice_minutes_time,
  tdw.sla_target,
  IF(tdw.days_worked < 0, 0, tdw.days_worked) AS days_worked,
  IF(tdw.days_off < 0, 0, tdw.days_off) AS days_off,
  CASE
    WHEN IF(tdw.days_worked < 0, 0, tdw.days_worked) <= sla_target THEN IF(tdw.days_worked < 0, 0, tdw.days_worked)
    ELSE 0
  END AS time_spent_solved_in_time,
  CASE
    WHEN IF(tdw.days_worked < 0, 0, tdw.days_worked) > sla_target THEN IF(tdw.days_worked < 0, 0, tdw.days_worked)
    ELSE 0
  END AS time_spent_not_solved_in_time,
  CASE
    WHEN IF(tdw.days_worked < 0, 0, tdw.days_worked) <= sla_target THEN TRUE
    ELSE FALSE
  END AS is_ticket_solved_in_time,
  CASE
    WHEN IF(tdw.days_worked < 0, 0, tdw.days_worked) <= sla_target
      OR ISNULL(tdw.days_worked) THEN FALSE
    ELSE TRUE
  END AS is_ticket_not_solved_in_time,
  btt.has_open_back_ticket,
  t.is_back_ticket,
  t.tags LIKE '%closed_by_merge%' AS is_closed_by_merge,
  t.is_call_answered,
  IF(
    t.front_or_back = 'front'
    AND DATE(t.ts_solved) >= DATE('2022-01-01')
    AND t.contact_theme_detail_tag IS NOT NULL
    AND t.team != 'Ong Back'
    AND t.area = 'CX'
    AND t.last_queue NOT IN ('Rescisão por Inadimplência [OFF][POS][BACK]',
      'Offboarding Reparos [OFF] [POS] [BACK]',
      'Offboarding pré saída [OFF] [POS] [BACK]',
      'Proteção QuintoAndar [OFF] [POS] [BACK]',
      'Rescisão - Despejo [OFF][POS][BACK]',
      'Rescisão 1 [OFF] [POS] [BACK]'
    ),
    TRUE,
    FALSE
  ) AS is_ticket_rate,
  t.ts_budget,
  t.ts_created,
  tdw.ts_sla_started,
  t.ts_solved,
  t.ts_closed,
  t.ts_updated,
  t.year,
  t.month,
  t.day
FROM
  tickets AS t
LEFT JOIN
  back_ticket_timestamps AS btt
    ON btt.id_front_ticket = t.id_ticket
LEFT JOIN
  ticket_days_worked AS tdw
    ON tdw.id_ticket = t.id_ticket
