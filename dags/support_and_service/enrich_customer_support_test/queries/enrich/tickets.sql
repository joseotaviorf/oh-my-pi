WITH incoming_tickets AS (
  SELECT
    id_ticket,
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
    ts_created,
    ts_solved,
    ts_closed,
    ts_updated,
    year,
    month,
    day
  FROM
    datalake_zendesk.tickets_current AS t
  WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
),
dedup_twilio_tickets AS (
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
  INNER JOIN
    datalake_customer_support_test.calls AS ca
      ON COALESCE(ca.id_call, ca.id_task) = it.id_call
  GROUP BY 1, 2
),
dedup_tickets AS (
  SELECT
    id_ticket,
    channel
  FROM
    dedup_twilio_tickets
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
    dedup_twilio_tickets AS dtt
      ON dtt.id_ticket = it.id_ticket
  WHERE
    dtt.id_ticket IS NULL
),
unique_tickets AS (
  SELECT
    dt.id_ticket,
    t.id_call,
    t.id_session,
    COALESCE(ch.queue_name, ca.queue_name, t.ticket_queue) AS queue,
    t.contact_ticket,
    t.task_sid_twilio,
    t.twilio_task,
    t.tags,
    t.description,
    t.status,
    t.analyst_email,
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
    dedup_tickets AS dt
      ON dt.id_ticket = t.id_ticket
  LEFT JOIN
    datalake_customer_support_test.chats AS ch
      ON ch.id_task = t.twilio_task
  LEFT JOIN
    datalake_customer_support_test.calls AS ca
      ON COALESCE(ca.id_call, ca.id_task) = t.id_call
),
ticket_queue AS (
  SELECT
    tq.id_ticket,
    FIRST(tq.queue) OVER (PARTITION BY tq.id_ticket ORDER BY tq.ts_created) AS first_queue,
    LAST(tq.queue) OVER (PARTITION BY tq.id_ticket ORDER BY tq.ts_created) AS last_queue,
    dc.front_or_back,
    dc.journey_step,
    dc.team,
    dc.area
  FROM
    unique_tickets AS tq
  LEFT JOIN
    datalake_gsheets_clean.department_control dc
      ON dc.department = tq.queue
),
tickets_with_queue AS (
  SELECT
    t.id_ticket,
    t.id_call,
    t.id_session,
    tq.first_queue,
    tq.last_queue,
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
    t.analyst_email,
    t.channel,
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
    unique_tickets AS t
  LEFT JOIN
    ticket_queue AS tq
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
    tickets_with_queue AS bt
  LEFT JOIN
    tickets_with_queue AS ft_chat
      ON ft_chat.id_session = bt.id_session
      AND ft_chat.is_back_ticket IS FALSE
  LEFT JOIN
    tickets_with_queue AS ft_call
      ON ft_call.task_sid_twilio = bt.task_sid_twilio
      AND ft_call.is_back_ticket IS FALSE
  WHERE
    bt.is_back_ticket IS TRUE
),
back_ticket_timestamps AS (
  SELECT
    id_front_ticket,
    ARRAY_AGG(id_back_ticket) AS back_ticket_list,
    SUM(CAST(status IN ('closed','deleted','solved') AS SMALLINT)) - COUNT(DISTINCT(id_back_ticket)) != 0 AS has_open_back_ticket,
    CAST((TO_UNIX_TIMESTAMP(MIN(ts_created)) - TO_UNIX_TIMESTAMP(MAX(ts_solved))) / 60.0 AS DOUBLE) AS total_backoffice_minutes_time
  FROM
    back_tickets
  GROUP BY 1
),
/*
TODO: the following 'sla' CTEs are a replica of the ones in datalake_customer_demand.base_tasks and were built with a
full load perspective on the table. They should be adapted in order to take full advantage of the MERGE operation and
update SLA incrementally - this means removing the EXPLODE(SEQUENCE(dt_start, COALESCE(dt_end, DATE(NOW())))) part
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
ticket_sla AS (
  SELECT
    t.id_ticket,
    MIN(
      CASE
        WHEN t.last_queue IN ('Proteção QuintoAndar [OFF] [POS] [BACK]', 'Rescisão - Despejo [OFF][POS][BACK]') THEN 21
        ELSE COALESCE(tst.sla, tds.sla_in_days, ts.sla_in_days, ujst.sla_in_days)
      END
    ) AS sla_target,
    t.ts_budget
  FROM
    tickets_with_queue AS t
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
      OR t.last_queue <> 'Offboarding Reparos [OFF] [POS] [BACK]'
    )
  GROUP BY ALL
)
SELECT DISTINCT
  t.id_ticket,
  t.id_call,
  t.id_session,
  t.first_queue,
  t.last_queue,
  t.status,
  t.channel,
  t.tags,
  t.description,
  t.analyst_email,
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
  ts.sla_target,
  btt.has_open_back_ticket,
  t.tags LIKE '%closed_by_merge%' AS is_closed_by_merge,
  t.is_call_answered,
  ts.ts_budget,
  t.ts_created,
  t.ts_solved,
  t.ts_closed,
  t.ts_updated,
  t.year,
  t.month,
  t.day
FROM
  tickets_with_queue AS t
LEFT JOIN
  back_ticket_timestamps AS btt
    ON btt.id_front_ticket = t.id_ticket
LEFT JOIN
  ticket_sla AS ts
    ON ts.id_ticket = t.id_ticket
