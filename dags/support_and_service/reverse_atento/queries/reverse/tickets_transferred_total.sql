WITH base AS (
  SELECT DISTINCT
    frc.sk_contact as sk_conversation,
    frc.sk_task AS sk_segment,
    frc.sk_ticket,
    da.email,
    dd.team,
    frc.status,
    dd.department,
    frc.transferred_from,
    frc.transferred_to,
    frc.is_first_interaction,
    frc.is_last_interaction,
    da.agent_organization,
    dt.theme,
    dt.theme_detail,
    CASE
      WHEN frc.status = 'TRANSFERRED'
        AND dd2.team <> 'Inside Sales'
        AND frc.is_first_department_interaction = True
      THEN 1
      ELSE 0
    END AS task_transferred,
    ROW_NUMBER() OVER (PARTITION BY frc.sk_contact ORDER BY frc.ts_created) AS segment_number,
    frc.ts_created AS ts_started
  FROM
    dw_customer_support.fact_received_contact frc
  LEFT JOIN
    dw_customer_support.dim_department dd
      ON dd.sk_department = frc.sk_department
  LEFT JOIN 
    dw_customer_support.dim_department dd2 
      ON dd2.department = frc.transferred_to
  LEFT JOIN
    dw_customer_support.dim_agent da
      ON frc.agent_email = da.email
  LEFT JOIN
    dw_customer_support.dim_taxonomy dt
      ON frc.sk_taxonomy = dt.sk_taxonomy
  WHERE
    frc.channel = 'chat'
    AND dd.front_or_back = 'front'
    AND dd.area = 'CX'
    AND dd.department IN (
      'CX Mudança [FRONT] [POS]'
      ,'CX Pagamentos [FRONT] [POS]'
      ,'CX Parceiros [FRONT] [PRE]'
      ,'CX Parceiros da Portaria [FRONT] [PRE]'
      ,'CX Propostas [FRONT] [PRE]'
      ,'CX Reparos [FRONT] [POS]'
      ,'CX Rescisão [FRONT] [POS]'
      ,'CX Visitas [FRONT] [PRE]'
      ,'Consultores imobiliários 5A'
      ,'CX Parceiros Compra e Venda [FRONT]')
    AND DATE_TRUNC('month', frc.ts_created) >= CURRENT_DATE - INTERVAL '6' MONTH
    AND (da.agent_organization = "atento" OR da.agent_organization = "atn")
),
transferred_segments AS (
  SELECT
    sk_conversation,
    sk_ticket,
    theme_detail,
    department,
    SUM(task_transferred) AS transferencias,
    COUNT(DISTINCT sk_conversation) AS tickets,
    MAX(CASE WHEN segment_number = 1 THEN department END) AS department_1,
    MAX(CASE WHEN segment_number = 1 THEN email END) AS op_1,
    MAX(CASE WHEN segment_number = 1 THEN transferred_to END) AS transferred_to_1,
    MAX(CASE WHEN segment_number = 2 THEN email END) AS op_2,
    MAX(CASE WHEN segment_number = 2 THEN transferred_to END) AS transferred_to_2,
    MAX(CASE WHEN segment_number = 3 THEN email END) AS op_3,
    MAX(CASE WHEN segment_number = 3 THEN transferred_to END) AS transferred_to_3,
    MAX(CASE WHEN segment_number = 4 THEN email END) AS op_4,
    MAX(CASE WHEN segment_number = 4 THEN transferred_to END) AS transferred_to_4,
    MAX(CASE WHEN segment_number = 5 THEN email END) AS op_5,
    MAX(CASE WHEN segment_number = 5 THEN transferred_to END) AS transferred_to_5,
    MAX(CASE WHEN segment_number = 6 THEN email END) AS op_6,
    MAX(CASE WHEN segment_number = 6 THEN transferred_to END) AS transferred_to_6,
    MAX(CASE WHEN segment_number = 7 THEN email END) AS op_7,
    MAX(CASE WHEN segment_number = 7 THEN transferred_to END) AS transferred_to_7,
    MAX(CASE WHEN segment_number = 8 THEN email END) AS op_8,
    MAX(CASE WHEN segment_number = 8 THEN transferred_to END) AS transferred_to_8,
    MAX(CASE WHEN segment_number = 9 THEN email END) AS op_9,
    MAX(CASE WHEN segment_number = 9 THEN transferred_to END) AS transferred_to_9,
    MAX(CASE WHEN segment_number = 10 THEN email END) AS op_10,
    MAX(CASE WHEN segment_number = 10 THEN transferred_to END) AS transferred_to_10,
    DATE(ts_started) AS dt_started
  FROM
    base
  GROUP BY ALL
)
,steps_definition as (
  SELECT
    sk_conversation,
    sk_ticket,
    theme_detail,
    transferencias,
    tickets,
    department,
    department_1,
    op_1,
    transferred_to_1,
    op_2,
    transferred_to_2,
    op_3,
    transferred_to_3,
    op_4,
    transferred_to_4,
    op_5,
    transferred_to_5,
    op_6,
    transferred_to_6,
    op_7,
    transferred_to_7,
    op_8,
    transferred_to_8,
    op_9,
    transferred_to_9,
    op_10,
    transferred_to_10,
    CASE
      WHEN
        SUM(transferencias) > 0
        AND transferred_to_2 IS NULL
      THEN '2'
      WHEN
        SUM(transferencias) > 0
        AND transferred_to_2 IS NOT NULL
        AND transferred_to_3  IS NULL
      THEN '3'
      WHEN
        SUM(transferencias) > 0
        AND transferred_to_2 IS NOT NULL
        AND transferred_to_3 IS NOT NULL
        AND transferred_to_4 IS NULL
      THEN '4'
      WHEN
        SUM(transferencias) > 0
        AND transferred_to_2 IS NOT NULL
        AND transferred_to_3 IS NOT NULL
        AND transferred_to_4 IS NOT NULL
        AND transferred_to_5 IS NULL
      THEN '5'
      WHEN
        SUM(transferencias) > 0
        AND transferred_to_2 IS NOT NULL
        AND transferred_to_3 IS NOT NULL
        AND transferred_to_4 IS NOT NULL
        AND transferred_to_5 IS NOT NULL
        AND transferred_to_6 IS NULL
      THEN '6'
      WHEN
        SUM(transferencias) > 0
        AND transferred_to_2 IS NOT NULL
        AND transferred_to_3 IS NOT NULL
        AND transferred_to_4 IS NOT NULL
        AND transferred_to_5 IS NOT NULL
        AND transferred_to_6 IS NOT NULL
        AND transferred_to_7 IS NULL
      THEN '7'
      WHEN
        SUM(transferencias) > 0
        AND transferred_to_2 IS NOT NULL
        AND transferred_to_3 IS NOT NULL
        AND transferred_to_4 IS NOT NULL
        AND transferred_to_5 IS NOT NULL
        AND transferred_to_6 IS NOT NULL
        AND transferred_to_7 IS NOT NULL
        AND transferred_to_8 IS NULL
      THEN '8'
      WHEN
        SUM(transferencias) > 0
        AND transferred_to_2 IS NOT NULL
        AND transferred_to_3 IS NOT NULL
        AND transferred_to_4 IS NOT NULL
        AND transferred_to_5 IS NOT NULL
        AND transferred_to_6 IS NOT NULL
        AND transferred_to_7 IS NOT NULL
        AND transferred_to_8 IS NOT NULL
        AND transferred_to_9 IS NULL
      THEN '9'
      WHEN
        SUM(transferencias) > 0
        AND transferred_to_2 IS NOT NULL
        AND transferred_to_3 IS NOT NULL
        AND transferred_to_4 IS NOT NULL
        AND transferred_to_5 IS NOT NULL
        AND transferred_to_6 IS NOT NULL
        AND transferred_to_7 IS NOT NULL
        AND transferred_to_8 IS NOT NULL
        AND transferred_to_9 IS NOT NULL
        AND transferred_to_10 IS NULL
      THEN '10'
      WHEN
        SUM(transferencias) > 0
        AND transferred_to_2 IS NOT NULL
        AND transferred_to_3 IS NOT NULL
        AND transferred_to_4 IS NOT NULL
        AND transferred_to_5 IS NOT NULL
        AND transferred_to_6 IS NOT NULL
        AND transferred_to_7 IS NOT NULL
        AND transferred_to_8 IS NOT NULL
        AND transferred_to_9 IS NOT NULL
        AND transferred_to_10 IS NOT NULL
      THEN '11 ou +'
    END AS quant_steps,
    dt_started
  FROM transferred_segments
GROUP BY ALL
)
SELECT
  sk_conversation,
  sk_ticket,
  theme_detail,
  transferencias,
  tickets,
  department,
  department_1,
  op_1,
  transferred_to_1,
  op_2,
  transferred_to_2,
  op_3,
  transferred_to_3,
  op_4,
  transferred_to_4,
  op_5,
  transferred_to_5,
  op_6,
  transferred_to_6,
  op_7,
  transferred_to_7,
  op_8,
  transferred_to_8,
  op_9,
  transferred_to_9,
  op_10,
  transferred_to_10,
  quant_steps,
  SUM(
    CASE
      WHEN transferencias <> 0
        AND quant_steps = '2'
        AND department_1 <> transferred_to_1
      THEN transferencias
      WHEN transferencias <> 0
        AND quant_steps = '3'
        AND department_1 <> transferred_to_2
      THEN transferencias
      ELSE 0
    END) as bot_error,
  SUM(
    CASE
      WHEN transferencias <> 0
        AND quant_steps = '2'
        AND department_1 = transferred_to_1
      THEN transferencias
      WHEN transferencias <> 0
        AND quant_steps = '3'
        AND department_1 = transferred_to_2
      THEN transferencias
      WHEN transferencias <> 0
        AND quant_steps  = '4'
        AND department_1 = transferred_to_3
      THEN transferencias
      WHEN transferencias <> 0
        AND quant_steps  = '5'
        AND department_1 = transferred_to_4
      THEN transferencias
      WHEN transferencias <> 0
        AND quant_steps  = '6'
        AND department_1 = transferred_to_5
      THEN transferencias
      WHEN transferencias <> 0
        AND quant_steps  = '7'
        AND department_1 = transferred_to_6
      THEN transferencias
      WHEN transferencias <> 0
        AND quant_steps  = '8'
        AND department_1 = transferred_to_7
      THEN transferencias
      WHEN transferencias <> 0
        AND quant_steps  = '9'
        AND department_1 = transferred_to_8
      THEN transferencias
      WHEN transferencias <> 0
        AND quant_steps  = '10'
        AND department_1 = transferred_to_9
      THEN transferencias
      WHEN transferencias <> 0
        AND quant_steps  = '11'
        AND department_1 = transferred_to_10
      THEN transferencias
      WHEN transferencias <> 0
        AND quant_steps = '4'
        AND department_1 <> transferred_to_3
      THEN transferencias
      WHEN transferencias <> 0
        AND quant_steps = '5'
        AND department_1 <> transferred_to_4
      THEN transferencias
      WHEN transferencias <> 0
        AND quant_steps  = '6'
        AND department_1 <> transferred_to_5
      THEN transferencias
      WHEN transferencias <> 0
        AND quant_steps  = '7'
        AND department_1 <> transferred_to_6
      THEN transferencias
      WHEN transferencias <> 0
        AND quant_steps  = '8'
        AND department_1 <> transferred_to_7
      THEN transferencias
      WHEN transferencias <> 0
        AND quant_steps  = '9'
        AND department_1 <> transferred_to_8
      THEN transferencias
      WHEN transferencias <> 0
        AND quant_steps  = '10'
        AND department_1 <> transferred_to_9
      THEN transferencias
      WHEN transferencias <> 0
        AND quant_steps  = '11 ou +'
        AND department_1 <> transferred_to_10
      THEN transferencias
      ELSE 0
  END ) AS human_error,
  dt_started,
  YEAR(CURRENT_DATE) AS year,
  MONTH(CURRENT_DATE) AS month,
  DAY(CURRENT_DATE) AS day,
  NOW() AS ts_load
FROM steps_definition
GROUP BY ALL