WITH base_tickets AS (
  SELECT
    DATE(ft.ts_solved) AS dt_started,
    dt.theme AS contact_theme_tag,
    dt.theme_detail AS contact_theme_detail,
    dd.front_or_back AS ticket_type,
    dt.journey,
    dt.sub_journey,
    dt.line_owner,
    dd.team,
    dd.department,
    COUNT(DISTINCT ft.sk_ticket) AS tickets
  FROM
    dw_customer_support.fact_tickets AS ft
  JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON dt.sk_taxonomy = ft.sk_taxonomy
        AND dt.theme_detail IS NOT NULL
  LEFT JOIN
    dw_customer_support.dim_department AS dd
      ON ft.sk_main_department = dd.sk_department
  WHERE
    ft.is_ticket_rate = TRUE
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
missing_tickets AS (
  SELECT
    DATE(ft.ts_solved) AS dt_started,
    dd.front_or_back AS ticket_type,
    COUNT(DISTINCT ft.sk_ticket) AS missing_theme_tickets
  FROM
    dw_customer_support.fact_tickets AS ft
  LEFT JOIN
    dw_customer_support.dim_department AS dd
      ON ft.sk_main_department = dd.sk_department
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON dt.sk_taxonomy = ft.sk_taxonomy
  WHERE
    dt.theme_detail IS NULL
    AND (
      ft.channel IN ('call', 'chat') AND ft.front_or_back = 'front'
      OR ft.channel = 'email' AND ft.front_or_back IN ('back', 'front')
    )
    AND ft.ts_solved >= '2022-01-01'
    AND dd.team <> 'Ong Back'
    AND dd.area = 'CX'
    AND dd.department NOT IN
      ('Rescisão por Inadimplência [OFF][POS][BACK]',
        'Offboarding Reparos [OFF] [POS] [BACK]',
        'Offboarding pré saída [OFF] [POS] [BACK]',
        'Proteção QuintoAndar [OFF] [POS] [BACK]',
        'Rescisão - Despejo [OFF][POS][BACK]',
        'Rescisão 1 [OFF] [POS] [BACK]'
      )
    AND (ft.channel <> 'call'
      OR (ft.channel = 'call'
        AND ft.ticket_origin IN ('call inapp', 'call inbound')
      )
    )
  GROUP BY 1, 2
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
base_themes AS (
  SELECT
    dt_started,
    ticket_type,
    COUNT(DISTINCT contact_theme_detail, ticket_type) AS qtd_theme_details,
    SUM(tickets) AS qt_tickets
  FROM
    base_tickets
  GROUP BY 1, 2
)
SELECT
  btkt.dt_started,
  btkt.contact_theme_tag,
  btkt.contact_theme_detail,
  btkt.ticket_type,
  btkt.journey,
  btkt.sub_journey,
  btkt.line_owner,
  btkt.team,
  btkt.department,
  SUM(btkt.tickets) AS total_tickets_identified,
  CAST(COALESCE((SUM(btkt.tickets)/bt.qt_tickets) * ac.contacts, 0) AS NUMERIC(12,2)) AS total_abandoned_calls_distributed,
  CAST(COALESCE((SUM(btkt.tickets)/bt.qt_tickets) * mt.missing_theme_tickets, 0) AS NUMERIC(12,2)) AS total_tickets_distributed,
  SUM(btkt.tickets) + CAST(COALESCE((SUM(btkt.tickets)/bt.qt_tickets) * mt.missing_theme_tickets, 0) AS NUMERIC(12,2)) + CAST(COALESCE((SUM(btkt.tickets)/bt.qt_tickets) * ac.contacts, 0) AS NUMERIC(12,2)) AS total_tickets_proportional
FROM
  base_tickets AS btkt
JOIN
  base_themes AS bt
    ON bt.dt_started = btkt.dt_started
    AND bt.ticket_type = btkt.ticket_type
LEFT JOIN
  missing_tickets AS mt
    ON mt.dt_started = btkt.dt_started
      AND mt.ticket_type = btkt.ticket_type
LEFT JOIN
  abandoned_calls AS ac
    ON ac.dt_started = btkt.dt_started
      AND ac.ticket_type = btkt.ticket_type
GROUP BY
  btkt.dt_started,
  btkt.contact_theme_tag,
  btkt.contact_theme_detail,
  btkt.ticket_type,
  btkt.journey,
  btkt.sub_journey,
  btkt.line_owner,
  btkt.team,
  btkt.department,
  bt.qt_tickets,
  mt.missing_theme_tickets,
  ac.contacts
