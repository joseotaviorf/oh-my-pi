WITH base_tickets as (
  SELECT 
    DATE_TRUNC('month', ft.ts_solved) AS started_month,
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
    AND dd.journey_step NOT IN ('Compra e Venda', 'Cross', 'Rental Manager')
    AND dd.team <> 'Ong Back'
    AND dd.area = 'CX'
  GROUP BY
    1,2,3,4,5,6,7,8
),
abandoned_calls AS (
    SELECT
        DATE_TRUNC('month', frc.ts_created) AS started_month,
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
)
SELECT
    date(started_month) AS started_month,
    contact_theme_tag,
    contact_theme_detail,
    ticket_type,
    journey,
    sub_journey,
    line_owner,
    team,
    SUM(CASE WHEN ticket_type = 'front' AND contact_theme_tag = 'Abandonado' THEN tickets END) AS total_abandoned_calls,
    SUM(tickets) AS total_tickets
FROM 
    final_table 
GROUP BY
    1,2,3,4,5,6,7,8
ORDER BY 
    1 DESC 