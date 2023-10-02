WITH
base_tickets AS (
  SELECT
    DATE(ft.ts_solved) AS dt_started,
    dt.theme AS contact_theme_tag,
    dt.theme_detail AS contact_theme_detail,
    dd.front_or_back AS ticket_type,
    dt.journey,
    dt.sub_journey,
    dt.line_owner,
    dd.team,
    COUNT(DISTINCT
        CASE
          WHEN ft.channel = 'email' THEN ft.sk_ticket
          WHEN dd.front_or_back = 'front' AND ft.channel = 'chat' AND dc.direction = 'inbound' THEN ft.sk_ticket
          WHEN dd.front_or_back = 'front' AND ft.channel = 'call' AND dc.direction = 'inbound' THEN ft.sk_ticket
          WHEN dd.front_or_back = 'front' AND ft.channel = 'call' AND dc.direction = 'outbound-api' THEN ft.sk_ticket
    END) AS tickets
  FROM
    dw_customer_support.fact_ticket AS ft
  JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON dt.sk_taxonomy = ft.sk_taxonomy
        AND dt.theme_detail IS NOT NULL
  LEFT JOIN
    dw_customer_support.dim_department AS dd
      ON ft.sk_main_department = dd.sk_department
  LEFT JOIN
    dw_customer_support.dim_channel AS dc
      ON ft.sk_channel = dc.sk_channel
  WHERE
    ft.main_department NOT IN ('Rescisão por Inadimplência [OFF][POS][BACK]', 'Offboarding Reparos [OFF] [POS] [BACK]', 'Offboarding pré saída [OFF] [POS] [BACK]', 'Proteção QuintoAndar [OFF] [POS] [BACK]', 'Rescisão - Despejo [OFF][POS][BACK]', 'Rescisão 1 [OFF] [POS] [BACK]')
    AND ft.ts_solved >= CAST('2022-01-01' AS DATE)
    AND dd.front_or_back IN ('back', 'front')
    AND dd.journey_step NOT IN ('Compra e Venda', 'Cross')
    AND dd.team <> 'Ong Back'
    AND dd.area = 'CX'
  GROUP BY
    1,2,3,4,5,6,7,8
),
missing_tickets AS (
  SELECT
    DATE(ft.ts_solved) AS dt_started,
    dd.front_or_back AS ticket_type,
    COUNT(DISTINCT
        CASE
          WHEN ft.channel = 'email' THEN ft.sk_ticket
          WHEN dd.front_or_back = 'front' AND ft.channel = 'chat' AND dc.direction = 'inbound' THEN ft.sk_ticket
          WHEN dd.front_or_back = 'front' AND ft.channel = 'call' AND dc.direction = 'inbound' THEN ft.sk_ticket
          WHEN dd.front_or_back = 'front' AND ft.channel = 'call' AND dc.direction = 'outbound-api' THEN ft.sk_ticket
    END) AS missing_theme_tickets
  FROM
    dw_customer_support.fact_ticket AS ft
  LEFT JOIN
    dw_customer_support.dim_department AS dd
      ON ft.sk_main_department = dd.sk_department
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON dt.sk_taxonomy = ft.sk_taxonomy
  LEFT JOIN
    dw_customer_support.dim_channel AS dc
      ON ft.sk_channel = dc.sk_channel
  WHERE
    ft.main_department NOT IN ('Rescisão por Inadimplência [OFF][POS][BACK]', 'Offboarding Reparos [OFF] [POS] [BACK]', 'Offboarding pré saída [OFF] [POS] [BACK]', 'Proteção QuintoAndar [OFF] [POS] [BACK]', 'Rescisão - Despejo [OFF][POS][BACK]', 'Rescisão 1 [OFF] [POS] [BACK]')
    AND dd.journey_step NOT IN ('Compra e Venda', 'Cross')
    AND ft.ts_solved >= CAST('2022-01-01' AS DATE)
    AND dd.front_or_back IN ('back', 'front')
    AND dt.theme_detail IS NULL
    AND dd.team <> 'Ong Back'
    AND dd.area = 'CX'
  GROUP BY
    1,2
),
abandoned_calls AS (
  SELECT
    DATE(frc.ts_created) AS dt_started,
    dd.front_or_back AS ticket_type,
    COUNT(DISTINCT frc.sk_contact) AS contacts
  FROM
    dw_customer_support.fact_received_contact AS frc
  LEFT JOIN
    dw_customer_support.dim_department AS dd
      ON frc.sk_department = dd.sk_department
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON dt.sk_taxonomy = frc.sk_taxonomy
  WHERE
    dd.front_or_back = 'front'
    AND dd.journey_step NOT IN ('Compra e Venda', 'Cross')
    AND dd.area = 'CX'
    AND frc.is_answered = false
    AND frc.channel = 'call' 
  GROUP BY
    1,2
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
  bt.qt_tickets,
  mt.missing_theme_tickets,
  ac.contacts