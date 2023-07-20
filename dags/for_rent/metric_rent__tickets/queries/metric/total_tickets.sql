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
            WHEN dd.front_or_back = 'back' THEN ft.sk_ticket
            WHEN dd.front_or_back = 'front' AND ft.channel = 'email' THEN ft.sk_ticket
            WHEN dd.front_or_back = 'front' AND ft.channel = 'chat' AND dc.direction = 'inbound' THEN ft.sk_ticket
            WHEN dd.front_or_back = 'front' AND ft.channel = 'call' AND dc.direction = 'inbound' THEN ft.sk_ticket
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
    ft.main_department NOT IN ('Offboarding Reparos [OFF] [POS] [BACK]', 'Offboarding pré saída [OFF] [POS] [BACK]', 'Proteção QuintoAndar [OFF] [POS] [BACK]', 'Rescisão - Despejo [OFF][POS][BACK]', 'Rescisão 1 [OFF] [POS] [BACK]')
    AND ft.ts_solved >= CAST('2022-01-01' AS DATE)
    AND dd.front_or_back IN ('back', 'front')
    AND dd.journey_step NOT IN ('Compra e Venda', 'Cross', 'Rental Manager')
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
            WHEN dd.front_or_back = 'back' THEN ft.sk_ticket
            WHEN dd.front_or_back = 'front' AND ft.channel = 'email' THEN ft.sk_ticket
            WHEN dd.front_or_back = 'front' AND ft.channel = 'chat' AND dc.direction = 'inbound' THEN ft.sk_ticket
            WHEN dd.front_or_back = 'front' AND ft.channel = 'call' AND dc.direction = 'inbound' THEN ft.sk_ticket
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
    ft.main_department NOT IN ('Offboarding Reparos [OFF] [POS] [BACK]', 'Offboarding pré saída [OFF] [POS] [BACK]', 'Proteção QuintoAndar [OFF] [POS] [BACK]', 'Rescisão - Despejo [OFF][POS][BACK]', 'Rescisão 1 [OFF] [POS] [BACK]')
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
    'Abandonado' AS contact_theme_tag,
    'Abandonado' AS contact_theme_detail,
    dd.front_or_back AS ticket_type,
    dt.journey,
    dt.sub_journey,
    dt.line_owner,
    dd.team,
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
    AND dd.journey_step NOT IN ('Compra e Venda', 'Cross', 'Rental Manager')
    AND dd.area = 'CX'
    AND frc.is_answered = false
    AND frc.channel = 'call'
  GROUP BY
    1,2,3,4,5,6,7,8
),
final_table AS (
  SELECT * FROM base_tickets
  UNION ALL 
  SELECT * FROM abandoned_calls
),
base_themes AS (
  SELECT
    dt_started,
    COUNT(DISTINCT contact_theme_detail, ticket_type) AS qtd_theme_details,
    SUM(tickets) AS qt_tickets
  FROM 
    final_table
  GROUP BY 1
)
SELECT
  ft.dt_started,
  ft.contact_theme_tag,
  ft.contact_theme_detail,
  ft.ticket_type,
  ft.journey,
  ft.sub_journey,
  ft.line_owner,
  ft.team,
  SUM(IF(ft.ticket_type = 'front' AND ft.contact_theme_tag = 'Abandonado', ft.tickets, 0)) AS total_abandoned_calls,
  SUM(ft.tickets) AS total_tickets_identified,
  CAST((SUM(ft.tickets)/bt.qt_tickets) * mt.missing_theme_tickets AS NUMERIC(12,2)) AS total_tickets_distributed,
  CAST(SUM(ft.tickets) + ((SUM(ft.tickets)/bt.qt_tickets) * mt.missing_theme_tickets) AS NUMERIC(12,2)) AS total_tickets_proportional
FROM 
  final_table AS ft
JOIN
  base_themes AS bt
    ON bt.dt_started = ft.dt_started
LEFT JOIN
  missing_tickets AS mt
    ON mt.dt_started = ft.dt_started
      AND mt.ticket_type = ft.ticket_type
GROUP BY
  ft.dt_started,
  ft.contact_theme_tag,
  ft.contact_theme_detail,
  ft.ticket_type,
  ft.journey,
  ft.sub_journey,
  ft.line_owner,
  ft.team, 
  bt.qt_tickets, 
  mt.missing_theme_tickets