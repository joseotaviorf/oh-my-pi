WITH missing_theme_tickets AS (
  SELECT DISTINCT
    front_or_back AS ticket_type,
    last_queue AS department,
    COUNT(DISTINCT id_ticket) AS missing_theme_tickets,
    DATE(ts_solved) AS dt_started
  FROM
    datalake_customer_support_test.tickets
  WHERE
    -- It's necessary to apply all Ticket Rate rules but considering tickets that have no theme (taxonomy)
    contact_theme_detail_tag IS NULL
    AND (
      channel IN ('CALL', 'CHAT') AND front_or_back = 'FRONT'
      OR channel = 'EMAIL' AND front_or_back IN ('BACK', 'FRONT')
    )
    AND ts_solved >= '2022-01-01'
    AND team <> 'Ong Back'
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
      channel != 'CALL'
      OR (
        channel = 'CALL'
        AND ticket_origin IN ('CALL INAPP', 'CALL INBOUND')
      )
    )
  GROUP BY 1, 2, 4
),
abandoned_calls AS (
  SELECT
    dc.front_or_back AS ticket_type,
    c.queue_name AS department,
    COUNT(DISTINCT(id_task)) AS contacts,
    DATE(ts_task_created) AS dt_started
  FROM
    datalake_customer_support_test.calls AS c
  LEFT JOIN
    datalake_gsheets_clean.department_control AS dc
      ON dc.department = c.queue_name
  WHERE
    dc.front_or_back = 'front'
    AND dc.area = 'CX'
    AND c.is_call_answered IS FALSE
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
    datalake_customer_support_test.tickets AS ut
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
)
SELECT
  CAST(t.id_ticket AS BIGINT) AS sk_ticket,
  COALESCE(t.id_user_main, -1) AS sk_user,
  COALESCE(CAST(t.id_session AS BIGINT), -1) AS sk_session,
  COALESCE(t.id_contract, -1) AS sk_contract,
  MD5(COALESCE(t.last_queue, "NULL")) AS sk_department,
  MD5(COALESCE(t.last_analyst_email, "NULL")) AS sk_analyst,
  MD5(
    CONCAT(
      COALESCE(t.step_tag, ''),
      COALESCE(t.customer_type_tag, ''),
      COALESCE(t.client_type, ''),
      COALESCE(t.request_type, ''),
      COALESCE(t.contact_motivation_tag, ''),
      COALESCE(t.contact_theme_tag, ''),
      COALESCE(t.contact_theme_detail_tag, '')
    )
  ) AS sk_taxonomy,
  t.channel, -- TODO: dim_channel
  t.direction, -- TODO: dim_channel
  t.ticket_origin, -- TODO: dim_channel
  t.front_or_back,
  t.ticket_rate_weight,
  tr.total_tickets_proportional,
  t.sla_target,
  t.days_worked,
  t.days_off,
  t.time_spent_solved_in_time,
  t.time_spent_not_solved_in_time,
  t.total_backoffice_minutes_time,
  t.is_ticket_solved_in_time,
  t.is_ticket_not_solved_in_time,
  t.is_ticket_rate,
  t.is_back_ticket,
  t.has_open_back_ticket,
  t.ts_created,
  t.ts_sla_started,
  t.ts_solved,
  t.ts_closed,
  t.ts_updated
FROM
  datalake_customer_support_test.tickets AS t
LEFT JOIN
  ticket_rate_proportion AS tr
    ON tr.id_ticket = t.id_ticket
