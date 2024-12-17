WITH segments AS (
  SELECT DISTINCT
    fcc.sk_ticket,
    fcc.sk_contact,
    fcc.sk_task AS sk_segment,
    fcc.sk_interaction,
    da.email AS agent_email,
    dt.theme,
    dt.theme_detail,
    fcc.customer_phone_number AS customer_phone,
    dd_prev.department AS transferred_from,
    dd.department,
    dd2.team AS transferred_to_team,
    dd2.department AS transferred_to,
    CASE
      WHEN fcc.channel = 'chat' THEN fcc.status
      WHEN fcc.channel = 'call' AND fcc.sk_task IS NULL THEN 'abandoned'
      WHEN fcc.channel = 'call'AND fcc.is_last_interaction = True THEN 'completed'
      WHEN fcc.channel = 'call' THEN 'transferred'
    END AS outcome,
    da.agent_organization,
    dd.team,
    fcc.channel,
    dd.area,
    dd.front_or_back,
    fcc.status,
    fd.department AS first_department,
    ld.department AS last_department,
    CASE
      WHEN fcc.status = 'transferred'
        AND dd2.team <> 'Inside Sales'
        AND fcc.is_first_department_interaction = TRUE
      THEN True
      ELSE False
    END AS task_transferred,
    CASE
      WHEN fcc.status = 'transferred'
        AND fcc.is_first_department_interaction = TRUE
        AND dd2.team <> 'Inside Sales'
        AND dd2.department IS NOT NULL
        AND dd_prev.department IS NULL
      THEN True
      ELSE False
    END AS first_transfer,
    fcc.is_last_interaction,
    fcc.ts_task_created AS ts_started,
    fcc.is_first_department_interaction,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day,
    NOW() AS ts_load
  FROM
    dw_customer_support.fact_customer_contacts AS fcc
  LEFT JOIN
    dw_customer_support.dim_department AS dd
      ON dd.sk_department = fcc.sk_department
  LEFT JOIN
    dw_customer_support.dim_department AS dd_prev
      ON dd_prev.sk_department = fcc.sk_prev_department
  LEFT JOIN
    dw_customer_support.dim_department AS dd2
      ON dd2.sk_department = fcc.sk_next_department
  LEFT JOIN
    dw_customer_support.dim_department AS fd
      ON fd.sk_department = fcc.sk_first_department
  LEFT JOIN
    dw_customer_support.dim_department AS ld
      ON ld.sk_department = fcc.sk_last_department
  LEFT JOIN
    dw_customer_support.dim_analyst AS da
      ON fcc.sk_analyst = da.sk_analyst
  LEFT JOIN
    dw_customer_support.dim_ticket AS dit
      ON fcc.sk_ticket = dit.sk_ticket
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON dt.sk_taxonomy = dit.sk_taxonomy
  WHERE
    fcc.channel = 'chat'
    AND dd.front_or_back = 'front'
    AND dd.area = 'CX'
    AND dd.department IN (
    'CX Mudança [FRONT] [POS]',
    'CX Pagamentos [FRONT] [POS]',
    'CX Parceiros [FRONT] [PRE]',
    'CX Parceiros da Portaria [FRONT] [PRE]',
    'CX Propostas [FRONT] [PRE]',
    'CX Reparos [FRONT] [POS]',
    'CX Rescisão [FRONT] [POS]',
    'CX Visitas [FRONT] [PRE]',
    'Consultores imobiliários 5A',
    'CX Parceiros Compra e Venda [FRONT]')
    AND DATE_TRUNC('month', fcc.ts_task_created) BETWEEN DATE('{load_start_date}') - INTERVAL '2' MONTH AND DATE('{load_end_date}')
    AND da.agent_organization IN ('atento','atn')
)
SELECT
  *,
  CASE
    WHEN
      (first_department = last_department
      OR (transferred_to != last_department))
      AND outcome = 'transferred' THEN 'human_error'
    ELSE 'bot_error'
  END AS transfer_reason,
  CASE
    WHEN
      is_last_interaction = true
      AND department != first_department THEN 'bot_error'
    WHEN
      is_last_interaction = false
      AND transferred_to != last_department
      AND outcome = 'transferred' THEN 'human_error'
    WHEN
      is_last_interaction = false
      AND transferred_to = last_department
      AND outcome = 'transferred' THEN 'department_correction'
  END AS transfer_reason_detailed
FROM
  segments