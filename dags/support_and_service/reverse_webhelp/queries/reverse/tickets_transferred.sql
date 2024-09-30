WITH first_departament AS (
  SELECT
    a.sk_contact,
    dd.department AS first_department
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
    dd.department AS last_department
  FROM
    dw_customer_support.fact_received_contact a
  LEFT JOIN
    dw_customer_support.dim_department dd
      ON dd.sk_department = a.sk_department
  WHERE is_last_interaction = true
)
,segments AS (
  SELECT DISTINCT
    frc.sk_contact AS sk_ticket,
    frc.sk_task AS sk_segment,
    dd.department,
    dd.team,
    da.agent_organization,
    da.email as agent_email,
    dt.theme,
    dt.theme_detail,
    fd.first_department,
    ld.last_department,
    frc.transferred_to,
    frc.is_last_interaction,
    CASE
      WHEN ch.id_chat IS NOT NULL THEN 'chat5a'
      ELSE 'whatsapp'
    END AS ticket_origin,
    CASE
      WHEN
        frc.status = 'TRANSFERRED'
        AND frc.is_first_department_interaction = True
        AND dd2.team <> 'Inside Sales' THEN 1
      ELSE 0 END AS task_transferred,
    CASE
      WHEN frc.status = 'IDLED' THEN 1
      ELSE 0
    END AS task_idled,
    CASE
      WHEN frc.status = 'EXPIRED' THEN 1
      ELSE 0
    END AS session_expired,
    CASE
      WHEN frc.channel = 'chat' THEN frc.status
      WHEN frc.channel = 'call' AND fct.sk_task IS NULL THEN 'ABANDONED'
      WHEN frc.channel = 'call'AND frc.is_last_interaction = True THEN 'COMPLETED'
      WHEN frc.channel = 'call' THEN 'TRANSFERRED'
    END AS status,
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
      datalake_quinto_messenger.chat as ch
        ON ch.id_session = frc.sk_session
    LEFT JOIN
    dw_customer_support.dim_agent as da
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
    AND dd.front_or_back = 'front'
    AND dd.area = 'CX'
    AND da.agent_organization IN ('wh','webhelp','webhelpbr')
    AND dd.department IN (
      'ProOwners [FRONT] [PRE] [POS]',
      'Rental Manager [FRONT] [BACK]',
      '[WH] Rental Manager GOLD [FRONT]'
    )
)
SELECT
  *,
  CASE
    WHEN
      (first_department = last_department
      OR (transferred_to != last_department))
      AND status = 'TRANSFERRED' then 'human_error'
    ELSE 'bot_error'
  END AS transfer_reason,
  CASE
    WHEN
      is_last_interaction = true
      AND department != first_department then 'bot_error'
    WHEN
      is_last_interaction = false
      AND transferred_to != last_department
      AND status = 'TRANSFERRED' then 'human_error'
    WHEN
      is_last_interaction = false
      AND transferred_to = last_department
      AND status = 'TRANSFERRED' then 'department_correction'
  END AS transfer_reason_detailed,
  YEAR(CURRENT_DATE - 1) AS year,
  MONTH(CURRENT_DATE - 1) AS month,
  DAY(CURRENT_DATE - 1) AS day,
  NOW() AS ts_load
FROM
  segments