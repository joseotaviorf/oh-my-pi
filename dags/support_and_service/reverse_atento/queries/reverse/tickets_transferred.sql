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
SELECT DISTINCT
  frc.sk_ticket,
  frc.sk_contact,
  frc.sk_task AS sk_segment,
  frc.agent_email,
  frc.customer_phone,
  frc.transferred_from,
  dd.department,
  frc.transferred_to,
  frc.status AS outcome,
  dd.team,
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
  frc.ts_created AS ts_started,
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
WHERE
  frc.channel = 'chat'
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
  AND DATE_TRUNC('month', frc.ts_created) >= CURRENT_DATE - INTERVAL '2' MONTH
  AND (da.agent_organization = "atento" OR da.agent_organization = "atn")
