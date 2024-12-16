WITH first_departament AS (
  SELECT
    a.sk_contact,
    dd.department AS first_department
  FROM
    dw_customer_support.fact_customer_contacts AS a
    LEFT JOIN
      dw_customer_support.dim_department dd
        ON dd.sk_department = a.sk_department
  WHERE
    is_first_interaction = TRUE
),
last_departament AS (
  SELECT
    a.sk_contact,
    dd.department AS last_department
  FROM
    dw_customer_support.fact_customer_contacts AS a
  LEFT JOIN
    dw_customer_support.dim_department dd
      ON dd.sk_department = a.sk_department
  WHERE
    is_last_interaction = TRUE
),
segments AS (
  SELECT DISTINCT
    fcc.sk_contact AS sk_ticket,
    fcc.sk_task AS sk_segment,
    dd.department,
    dd.team,
    da.agent_organization,
    da.email AS agent_email,
    dt.theme,
    dt.theme_detail,
    dd_first.department AS first_department,
    dd_last.department AS last_department,
    dd2.department AS transferred_to,
    fcc.is_last_interaction,
    CASE
      WHEN fcc.origin = 'chat in app' THEN 'chat5a'
      ELSE 'whatsapp'
    END AS ticket_origin,
    CASE
      WHEN fcc.status = 'transferred' AND fcc.is_first_department_interaction = TRUE
        AND dd2.team <> 'Inside Sales' THEN 1
      ELSE 0
    END AS task_transferred,
    CASE
      WHEN fcc.status = 'idled' THEN 1
      ELSE 0
    END AS task_idled,
    CASE
      WHEN fcc.status = 'expired' THEN 1
      ELSE 0
    END AS session_expired,
    fcc.status,
    fcc.ts_task_created AS ts_started
  FROM
    dw_customer_support.fact_customer_contacts AS fcc
  LEFT JOIN
    dw_customer_support.dim_department AS dd
      ON dd.sk_department = fcc.sk_department
  LEFT JOIN
    dw_customer_support.dim_department AS dd2
      ON dd2.department = fcc.sk_next_department
  LEFT JOIN
    dw_customer_support.dim_department AS dd_first
      ON dd_first.sk_department = fcc.sk_first_department
  LEFT JOIN
    dw_customer_support.dim_department AS dd_last
      ON dd_last.sk_department = fcc.sk_last_department
  LEFT JOIN
    dw_customer_support.dim_analyst as da
      ON fcc.sk_analyst = da.sk_analyst
  LEFT JOIN
    dw_customer_support.dim_ticket AS dit
      ON dit.sk_ticket = fcc.sk_ticket
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON dit.sk_taxonomy = dt.sk_taxonomy
  WHERE
    fcc.channel = 'chat'
    AND dd.front_or_back = 'front'
    AND dd.area = 'CX'
    AND da.agent_organization IN ('wh', 'webhelp', 'webhelpbr')
    AND dd.department IN (
      'ProOwners [FRONT] [PRE] [POS]',
      'Rental Manager [FRONT] [BACK]',
      '[WH] Rental Manager GOLD [FRONT]'
    )
)
SELECT
  *,
  CASE
    WHEN (first_department = last_department OR transferred_to != last_department)
      AND status = 'transferred' THEN 'human_error'
    ELSE 'bot_error'
  END AS transfer_reason,
  CASE
    WHEN is_last_interaction = TRUE
      AND department != first_department THEN 'bot_error'
    WHEN is_last_interaction = FALSE AND transferred_to != last_department
      AND status = 'transferred' THEN 'human_error'
    WHEN is_last_interaction = FALSE AND transferred_to = last_department
      AND status = 'transferred' THEN 'department_correction'
  END AS transfer_reason_detailed,
  YEAR(CURRENT_DATE - 1) AS year,
  MONTH(CURRENT_DATE - 1) AS month,
  DAY(CURRENT_DATE - 1) AS day,
  NOW() AS ts_load
FROM
  segments
