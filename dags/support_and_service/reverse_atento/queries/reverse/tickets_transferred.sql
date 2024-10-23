WITH first_departament AS (
  SELECT
    a.sk_contact,
    dd.department as first_department
  FROM
    dw_customer_support.fact_received_contact a
    LEFT JOIN
      dw_customer_support.dim_department dd
        ON dd.sk_department = a.sk_department
  WHERE is_first_interaction = true
)
,last_departament AS (
  SELECT
    a.sk_contact,
    dd.department as last_department
  FROM
    dw_customer_support.fact_received_contact a
  LEFT JOIN
    dw_customer_support.dim_department dd
      ON dd.sk_department = a.sk_department
  WHERE is_last_interaction = true
)
,segments AS (
  SELECT DISTINCT
    frc.sk_ticket,
    frc.sk_contact,
    frc.sk_task AS sk_segment,
    frc.sk_interaction,
    frc.agent_email,
    dt.theme,
    dt.theme_detail,
    frc.customer_phone,
    frc.transferred_from,
    dd.department,
    LEAD(dd.team) OVER(PARTITION BY frc.sk_contact ORDER BY frc.ts_created) AS transferred_to_team,
    frc.transferred_to,
    CASE
      WHEN frc.channel = 'chat' THEN frc.status
      WHEN frc.channel = 'call' AND fct.sk_task IS NULL THEN 'ABANDONED'
      WHEN frc.channel = 'call'AND frc.is_last_interaction = True THEN 'COMPLETED'
      WHEN frc.channel = 'call' THEN 'TRANSFERRED'
    END AS outcome,
    da.agent_organization,
    dd.team,
    frc.channel,
    dd.area,
    dd.front_or_back,
    frc.status,
    fd.first_department,
    ld.last_department,
    CASE
      WHEN frc.status = 'TRANSFERRED'
        AND dd2.team <> 'Inside Sales'
        AND frc.is_first_department_interaction = TRUE
      THEN True
      ELSE False
    END AS task_transferred,
    CASE
      WHEN frc.status = 'TRANSFERRED'
        AND frc.is_first_department_interaction = TRUE
        AND dd2.team <> 'Inside Sales'
        AND frc.transferred_to IS NOT NULL
        AND transferred_from IS NULL
      THEN True
      ELSE False
    END AS first_transfer,
    frc.is_last_interaction,
    frc.ts_created AS ts_started,
    frc.is_first_department_interaction,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day,
    NOW() AS ts_load
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
    first_departament fd
      ON fd.sk_contact = frc.sk_contact
  LEFT JOIN
    last_departament ld
      ON ld.sk_contact = frc.sk_contact
  LEFT JOIN
    dw_call.fact_call_tasks AS fct
      ON fct.sk_task = frc.sk_reservation
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON frc.sk_taxonomy = dt.sk_taxonomy
  WHERE
    frc.channel = 'chat'
)
,segments_final AS (
  SELECT
    *
  FROM
    segments
  WHERE
    front_or_back = 'front'
    AND area = 'CX'
    AND department IN (
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
    AND DATE_TRUNC('month', ts_started) >= CURRENT_DATE - INTERVAL '2' MONTH
    AND (agent_organization = 'atento' OR agent_organization = 'atn')
)
SELECT
  *,
  CASE
    WHEN
      (first_department = last_department
      OR (transferred_to != last_department))
      AND outcome = 'TRANSFERRED' THEN 'human_error'
    ELSE 'bot_error'
  END AS transfer_reason,
  CASE
    WHEN
      is_last_interaction = true
      AND department != first_department THEN 'bot_error'
    WHEN
      is_last_interaction = false
      AND transferred_to != last_department
      AND outcome = 'TRANSFERRED' THEN 'human_error'
    WHEN
      is_last_interaction = false
      AND transferred_to = last_department
      AND outcome = 'TRANSFERRED' THEN 'department_correction'
  END AS transfer_reason_detailed
FROM segments_final