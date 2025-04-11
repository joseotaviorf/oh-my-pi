WITH missing_theme_tickets AS (
  SELECT DISTINCT
    front_or_back AS ticket_type,
    last_queue AS department,
    COUNT(DISTINCT id_ticket) AS missing_theme_tickets,
    DATE(ts_solved) AS dt_started
  FROM
    datalake_customer_support.tickets
  WHERE
    -- It's necessary to apply all Ticket Rate rules but considering tickets that have no theme (taxonomy)
    contact_theme_detail_tag IS NULL
    AND (
      channel IN ('call', 'chat') AND front_or_back = 'front'
      OR channel = 'email' AND front_or_back IN ('back', 'front')
    )
    AND ts_solved >= '2022-01-01'
    AND team != 'Ong Back'
    AND area = 'CX'
    AND last_queue NOT IN (
      'Rescisão por Inadimplência [OFF][POS][BACK]',
      'Offboarding Reparos [OFF] [POS] [BACK]',
      'Offboarding pré saída [OFF] [POS] [BACK]',
      'Proteção QuintoAndar [OFF] [POS] [BACK]',
      'Rescisão - Despejo [OFF][POS][BACK]',
      'Rescisão 1 [OFF] [POS] [BACK]'
    )
    AND (
      channel != 'call'
      OR (
        channel = 'call'
        AND ticket_origin IN ('call inapp', 'call inbound')
      )
    )
  GROUP BY 1, 2, 4
),
abandoned_tasks AS (
  SELECT DISTINCT
    fcc.sk_task AS id_task,
    dd.front_or_back AS ticket_type,
    dd.department,
    DATE(fcc.ts_task_created) AS dt_started
  FROM
    dw_customer_support.fact_customer_contacts AS fcc
  LEFT JOIN
    dw_customer_support.dim_department AS dd
      ON fcc.sk_department = dd.sk_department
  WHERE
    fcc.channel = 'call'
    AND dd.front_or_back = 'front'
    AND dd.area = 'CX'
    AND fcc.is_contact_answered IS FALSE
    AND fcc.direction != 'outbound'
    AND fcc.ts_task_created >= '2023-01-01'
  UNION ALL
  SELECT DISTINCT
    fcc.sk_task AS id_task,
    dd.front_or_back AS ticket_type,
    dd.department,
    DATE(fcc.ts_task_created) AS dt_started
  FROM
    dw_customer_support.fact_customer_contacts AS fcc
  LEFT JOIN
    dw_customer_support.dim_department AS dd
      ON fcc.sk_department = dd.sk_department
  WHERE
    fcc.channel = 'call'
    AND dd.front_or_back = 'front'
    AND dd.area = 'CX'
    AND fcc.is_contact_answered IS TRUE
    AND fcc.direction != 'outbound'
    AND fcc.ts_task_created >= '2023-01-01'
    AND status = 'abandoned'
),
abandoned_calls AS (
  SELECT
    ticket_type,
    department,
    COUNT(DISTINCT(id_task)) AS contacts,
    dt_started
  FROM
    abandoned_tasks
  GROUP BY 1, 2, 4
),
ticket_rate_proportion AS (
  -- For the Ticket Rate proportional calculation, we're considering only tickets marked as Ticket Rate
  SELECT DISTINCT
    ut.id_ticket,
    CAST(
      ut.ticket_rate_weight * (
        1 + COALESCE(
          1 / (COUNT(ut.id_ticket) OVER(PARTITION BY DATE(ut.ts_solved), ut.front_or_back, ut.last_queue))
          * mt.missing_theme_tickets, 0
        )
        + COALESCE(
          1 / (COUNT(ut.id_ticket) OVER(PARTITION BY DATE(ut.ts_solved), ut.front_or_back, ut.last_queue))
          * ac.contacts, 0
        )
      ) AS DOUBLE
    ) AS total_tickets_proportional
  FROM
    datalake_customer_support.tickets AS ut
  LEFT JOIN
    missing_theme_tickets AS mt
      ON mt.dt_started = DATE(ut.ts_solved)
      AND mt.ticket_type = ut.front_or_back
      AND mt.department = ut.last_queue
  LEFT JOIN
    abandoned_calls AS ac
      ON ac.dt_started = DATE(ut.ts_solved)
      AND ac.ticket_type = ut.front_or_back
      AND ac.department = ut.last_queue
  WHERE
    ut.is_ticket_rate = TRUE
),
ticket_comment_metrics AS (
  SELECT
    tc.id_ticket,
    SUM(CASE WHEN tc.is_public THEN 1 ELSE 0 END) AS total_public_comments,
    SUM(CASE WHEN NOT tc.is_public THEN 1 ELSE 0 END) AS total_private_comments,
    MAX(CASE WHEN is_public AND zu.role = 'end-user' THEN tc.ts_created END) AS ts_latest_customer_comment,
    MAX(CASE WHEN is_public AND zu.role = 'agent' THEN tc.ts_created END) AS ts_latest_analyst_comment
  FROM
    datalake_zendesk_clean.ticket_comments AS tc
  LEFT JOIN
    datalake_support_users.zendesk_users AS zu
      ON zu.id_user_zendesk = tc.id_author
  GROUP BY 1
)
SELECT
  CAST(t.id_ticket AS BIGINT) AS sk_ticket,
  COALESCE(t.id_user_main, -1) AS sk_user,
  COALESCE(CAST(tc.id_submitter AS BIGINT), -1) AS sk_zendesk_submitter_user,
  COALESCE(CAST(tc.id_requester AS BIGINT), -1) AS sk_zendesk_requester_user,
  COALESCE(CAST(tc.id_assignee AS BIGINT), -1) AS sk_zendesk_assignee_user,
  CAST(COALESCE(tc.id_problem_ticket, -1) AS BIGINT) AS sk_problem_ticket,
  COALESCE(CAST(t.id_session AS BIGINT), -1) AS sk_session,
  COALESCE(t.id_contract, -1) AS sk_contract,
  tc.offer_ids[0] AS sk_sale_offer,
  COALESCE(CAST(t.id_house AS BIGINT), -1) AS sk_house,
  MD5(COALESCE(t.first_queue, "NULL")) AS sk_first_department,
  MD5(COALESCE(t.last_queue, "NULL")) AS sk_main_department,
  MD5(COALESCE(t.first_analyst_email, "NULL")) AS sk_first_analyst,
  MD5(COALESCE(t.last_analyst_email, "NULL")) AS sk_last_analyst,
  MD5(
    CONCAT(
      COALESCE(t.step_tag, 'step_tag'),
      COALESCE(t.customer_type_tag, 'customer_type_tag'),
      COALESCE(t.client_type, 'client_type'),
      COALESCE(t.request_type, 'request_type'),
      COALESCE(t.contact_motivation_tag, 'contact_motivation_tag'),
      COALESCE(t.contact_theme_tag, 'contact_theme_tag'),
      COALESCE(t.contact_theme_detail_tag, 'contact_theme_detail_tag')
    )
  ) AS sk_taxonomy, 
  t.channel, -- TODO: dim_channel
  t.direction, -- TODO: dim_channel
  t.ticket_origin, -- TODO: dim_channel
  t.front_or_back,
  t.ticket_rate_weight,
  tr.total_tickets_proportional,
  tc.group_stations AS total_group_stations,
  tc.assignee_stations AS total_assignee_stations,
  tc.reply_time_min_calendar,
  tc.first_resolution_time_min_calendar,
  tc.full_resolution_time_min_calendar,
  tc.requester_wait_time_min_calendar,
  tc.agent_wait_time_min_calendar,
  tc.on_hold_time_min_calendar,
  tc.reply_time_min_business,
  tc.first_resolution_time_min_business,
  tc.full_resolution_time_min_business,
  tc.requester_wait_time_min_business,
  tc.agent_wait_time_min_business,
  tc.on_hold_time_min_business,
  tc.replies,
  tc.reopens,
  t.sla_target,
  t.days_elapsed_calendar,
  t.days_elapsed_business,
  t.days_off,
  tcm.total_public_comments,
  tcm.total_private_comments,
  t.is_backlog_in_time,
  t.is_call_answered,
  t.is_ticket_rate,
  t.is_back_ticket,
  t.has_open_back_ticket,
  t.ts_created,
  t.ts_created_twilio,
  t.ts_sla_started,
  t.ts_solved,
  t.ts_closed,
  t.ts_updated,
  tcm.ts_latest_customer_comment,
  tcm.ts_latest_analyst_comment,
  NOW() AS ts_load
FROM
  datalake_customer_support.tickets AS t
LEFT JOIN
  ticket_rate_proportion AS tr
    ON tr.id_ticket = t.id_ticket
LEFT JOIN
  datalake_zendesk.tickets_current AS tc
    ON tc.id_ticket = t.id_ticket
LEFT JOIN
  ticket_comment_metrics AS tcm
    ON tcm.id_ticket = t.id_ticket
