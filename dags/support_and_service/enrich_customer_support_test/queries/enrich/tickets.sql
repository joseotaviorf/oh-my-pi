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
departments AS (
  SELECT
    department,
    journey_step,
    area,
    team,
    front_or_back
  FROM
    datalake_gsheets_clean.department_control
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY department ORDER BY journey_step DESC) = 1
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
    type,
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
    ut.id_ticket,
    t.id_problem_ticket,
    t.id_user_main,
    t.id_contract,
    t.id_call,
    t.id_session,
    COALESCE(ch.id_task, ca1.id_task, ca2.id_call) AS id_twilio,
    CASE
      WHEN ut.channel = 'chat' THEN ch.queue_name
      WHEN ut.channel = 'call' THEN COALESCE(ca1.queue_name, ca2.queue_name)
      ELSE t.ticket_queue
    END AS queue,
    t.contact_ticket,
    t.task_sid_twilio,
    t.twilio_task,
    t.tags,
    t.type,
    t.description,
    t.status,
    CASE
      WHEN ut.channel = 'chat' THEN ch.worker_email
      WHEN ut.channel = 'call' THEN COALESCE(ca1.worker_email, ca2.worker_email)
      ELSE t.analyst_email
    END AS analyst_email,
    ch.source,
    CASE
      WHEN COALESCE(ca1.direction, ca2.direction) IN ('outbound-api', 'outbound')
        OR COALESCE(ca1.channel_type, ca2.channel_type) = 'call-in-app' THEN 'OUTBOUND'
      WHEN COALESCE(ca1.direction, ca2.direction) = 'inbound' THEN 'INBOUND'
      WHEN t.tags LIKE '%"ticket_ativo"%' THEN 'OUTBOUND'
      ELSE 'INBOUND'
    END AS direction,
    CASE
      WHEN COALESCE(ca1.origin, ca2.origin) IS NOT NULL THEN CONCAT('CALL ', COALESCE(ca1.origin, ca2.origin))
      WHEN ch.source = 'IN APP' THEN 'CHAT INAPP'
      WHEN ch.source = 'WHATSAPP' THEN ch.source
      ELSE "N/A"
    END AS ticket_origin,
    ut.channel,
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
    COALESCE(ca1.is_call_answered, ca2.is_call_answered) AS is_call_answered,
    t.ts_budget,
    t.ts_created,
    COALESCE(ca1.ts_reservation_created, ca2.ts_reservation_created, ch.ts_created) AS ts_created_twilio,
    t.ts_solved,
    t.ts_closed,
    t.ts_updated,
    t.year,
    t.month,
    t.day
  FROM
    incoming_tickets AS t
  INNER JOIN
    unique_tickets AS ut
      ON ut.id_ticket = t.id_ticket
  LEFT JOIN
    datalake_customer_support_test.chats AS ch
      ON ch.id_task = t.twilio_task
  LEFT JOIN
    datalake_customer_support_test.calls AS ca1
      ON ca1.id_task = t.id_call
      AND STARTSWITH(t.id_call, "WT")
  LEFT JOIN
    datalake_customer_support_test.calls AS ca2
      ON ca2.id_call = t.id_call
      AND STARTSWITH(t.id_call, "CA")
),
ticket_queue_attributes AS (
  WITH queue_metrics AS (
    SELECT DISTINCT
      id_ticket,
      FIRST(queue) OVER (PARTITION BY id_ticket ORDER BY ts_created_twilio) AS first_queue,
      FIRST(queue) OVER (PARTITION BY id_ticket ORDER BY ts_created_twilio DESC) AS last_queue,
      FIRST(analyst_email) OVER (PARTITION BY id_ticket ORDER BY ts_created_twilio) AS first_analyst_email,
      FIRST(analyst_email) OVER (PARTITION BY id_ticket ORDER BY ts_created_twilio DESC) AS last_analyst_email
    FROM
      tickets_per_task
  )
  SELECT
    tq.id_ticket,
    tq.first_queue,
    tq.last_queue,
    tq.first_analyst_email,
    tq.last_analyst_email,
    LOWER(NULLIF(NULLIF(dc.front_or_back, '-'), '')) AS front_or_back,
    dc.journey_step,
    dc.team,
    dc.area
  FROM
    queue_metrics AS tq
  LEFT JOIN
    departments AS dc
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
    t.id_twilio,
    tq.first_queue,
    tq.last_queue,
    tq.first_analyst_email,
    tq.last_analyst_email,
    t.contact_ticket,
    t.task_sid_twilio,
    t.twilio_task,
    t.tags,
    t.type,
    t.description,
    CASE
      WHEN front_or_back = 'back'
        AND t.tags NOT LIKE '%bot_end_conversation%'
        AND t.tags NOT LIKE '%closed_by_merge%'
        AND t.tags LIKE '%tarefa_atendimento_escalado%' THEN TRUE
      ELSE FALSE
    END AS is_back_ticket,
    t.direction,
    t.ticket_origin,
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
    EXPLODE(SEQUENCE(dt_start, COALESCE(dt_end, "{load_end_date}"))) AS dt_reference
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
      EXPLODE(SEQUENCE(dt_start, COALESCE(dt_end, "{load_end_date}"))) AS dt_reference
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
      EXPLODE(SEQUENCE(dt_start, COALESCE(dt_end, "{load_end_date}"))) AS dt_reference
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
    MAX(
      CASE
        WHEN t.last_queue IN ('Proteção QuintoAndar [OFF] [POS] [BACK]', 'Rescisão - Despejo [OFF][POS][BACK]') THEN 21
        ELSE COALESCE(tst.sla, tds.sla_in_days, ts.sla_in_days, ujst.sla_in_days)
      END
    ) AS sla_target,
    MAX(
      CASE
        WHEN t.ts_budget IS NOT NULL
          AND t.ts_budget >= ts_created - INTERVAL 3 HOUR
          AND t.ts_budget < COALESCE(ts_solved, TIMESTAMP("{load_end_date}")) THEN t.ts_budget
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
      AND t.ts_created BETWEEN tst.dt_start AND COALESCE(tst.dt_end, TIMESTAMP("{load_end_date}"))
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
    MAX(sla_target) OVER(PARTITION BY id_ticket) AS sla_target,
    SEQUENCE(
      DATE(ts_sla_started),
      COALESCE(DATE(ts_solved), "{load_end_date}")
    ) AS dt_interval,
    ts_sla_started,
    ts_solved
  FROM
    ticket_sla_target
),
ticket_days_off AS (
  SELECT
    id_ticket,
    sla_target,
    ARRAY_SIZE(
      ARRAY_INTERSECT(dt_interval, (SELECT ARRAY_AGG(dt_non_working) FROM weekends_and_holidays))
    ) AS days_off,
    ts_sla_started,
    ts_solved
  FROM
    ticket_date_interval
),
ticket_days_elapsed AS (
  SELECT
    id_ticket,
    sla_target,
    COALESCE(days_off, 0) AS days_off,
    COALESCE(
      DATEDIFF(COALESCE(ts_solved, "{load_end_date}"), DATE(ts_sla_started)),
      0
    ) AS days_elapsed_calendar,
    ts_sla_started
  FROM
    ticket_days_off
),
ticket_sla_metrics AS (
  SELECT
    id_ticket,
    sla_target,
    days_off,
    days_elapsed_calendar,
    CASE
      WHEN days_elapsed_calendar - days_off < 0 THEN 0
      ELSE days_elapsed_calendar - days_off
    END AS days_elapsed_business,
    ts_sla_started
  FROM
    ticket_days_elapsed
),
ticket_metrics AS (
  SELECT DISTINCT
    t.id_ticket,
    t.id_problem_ticket,
    t.id_user_main,
    t.id_contract,
    t.id_call,
    t.id_session,
    t.id_twilio,
    t.first_queue,
    t.last_queue,
    t.first_analyst_email,
    t.last_analyst_email,
    t.front_or_back,
    t.journey_step,
    tr.sub_journey,
    t.team,
    t.area,
    t.status,
    t.channel AS channel,
    t.direction,
    t.ticket_origin,
    t.tags,
    t.type,
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
    tsm.sla_target,
    CASE
      WHEN tsm.days_elapsed_business < 0
        OR tsm.days_elapsed_business IS NULL THEN 0
      ELSE tsm.days_elapsed_business
    END AS days_elapsed_business,
    tsm.days_elapsed_calendar,
    COALESCE(tsm.days_off, 0) AS days_off,
    CASE
      WHEN tsm.days_elapsed_business <= tsm.sla_target THEN TRUE
      ELSE FALSE
    END AS is_backlog_in_time,
    btt.has_open_back_ticket,
    t.is_back_ticket,
    t.tags LIKE '%closed_by_merge%' AS is_closed_by_merge,
    t.is_call_answered,
    CASE
      WHEN t.channel IN ('call', 'chat')
        AND t.front_or_back = 'front'
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
        )
        AND t.ticket_origin != "CALL OUTBOUND" THEN TRUE
      WHEN t.channel IN ('email', 'whatsapp')
        AND t.front_or_back IN ('front', 'back')
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
        )
        AND NOT (
          t.last_queue = 'ReclameAqui [CE] [POS] [BACK]'
          AND t.type = 'problem'
        ) THEN TRUE
      ELSE FALSE
    END AS is_ticket_rate,
    t.ts_budget,
    t.ts_created,
    COALESCE(tsm.ts_sla_started, t.ts_created) AS ts_sla_started,
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
    ticket_sla_metrics AS tsm
      ON tsm.id_ticket = t.id_ticket
  LEFT JOIN
    datalake_gsheets_clean.ticket_rate_classification AS tr
      ON t.contact_theme_detail_tag = tr.micro_taxonomy
        AND t.contact_theme_tag = tr.macro_taxonomy
)
SELECT
  id_ticket,
  id_problem_ticket,
  id_user_main,
  id_contract,
  id_call,
  id_session,
  id_twilio,
  first_queue,
  last_queue,
  first_analyst_email,
  last_analyst_email,
  front_or_back,
  journey_step,
  team,
  area,
  status,
  channel,
  direction,
  ticket_origin,
  tags,
  type,
  description,
  request_type,
  client_type,
  step_tag,
  customer_type_tag,
  contact_theme_tag,
  contact_motivation_tag,
  contact_theme_detail_tag,
  custom_fields,
  reopens,
  replies,
  back_ticket_list,
  total_backoffice_minutes_time,
  sla_target,
  days_elapsed_business,
  days_elapsed_calendar,
  days_off,
  CASE
    WHEN sub_journey IN ('Contract to Entrance', 'Listing & Search', 'Offboarding', 'Onboarding', 'Visits to Offer')
      THEN 'FOR RENT'
    WHEN sub_journey = 'For Sale' THEN 'FOR SALE'
    WHEN sub_journey = 'Partners' THEN 'PARTNERS'
    ELSE NULL
  END AS context,
  CASE
    WHEN is_ticket_rate AND sub_journey = 'Ongoing' THEN
      CASE
        WHEN front_or_back = 'front' THEN 15
        WHEN front_or_back = 'back' THEN 30
      END
    WHEN is_ticket_rate AND sub_journey IN (
      'Contract to Entrance', 'For Sale',
      'Listing & Search', 'Offboarding',
      'Onboarding', 'Partners', 'Visits to Offer'
    ) THEN
      CASE
        WHEN front_or_back = 'front' THEN 1
        WHEN front_or_back = 'back' THEN 2
      END
    ELSE NULL
  END AS ticket_rate_weight,
  has_open_back_ticket,
  is_backlog_in_time,
  is_back_ticket,
  is_closed_by_merge,
  is_call_answered,
  is_ticket_rate,
  ts_budget,
  ts_created,
  ts_sla_started,
  ts_solved,
  ts_closed,
  ts_updated,
  year,
  month,
  day
FROM
  ticket_metrics
