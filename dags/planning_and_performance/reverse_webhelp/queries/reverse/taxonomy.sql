WITH base AS (
  SELECT
    NULLIF(fcc.sk_ticket, -1) AS sk_ticket,
    fcc.channel,
    fcc.ts_task_created AS ts_created,
    dd.department,
    dd.front_or_back,
    dt.customer_type_tag AS customer_type,
    dt.motivation,
    dt.theme,
    dt.theme_detail,
    dt.journey,
    dt.sub_journey,
    da.agent_organization,
    da.email
  FROM
    dw_customer_support.fact_customer_contacts AS fcc
  LEFT JOIN
    dw_customer_support.dim_ticket AS dit
      ON dit.sk_ticket = fcc.sk_ticket
  LEFT JOIN
    dw_customer_support.dim_department AS dd
      ON dd.sk_department = fcc.sk_department
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON dit.sk_taxonomy = dt.sk_taxonomy
  LEFT JOIN
    dw_customer_support.dim_analyst AS da
      ON da.sk_analyst = fcc.sk_analyst
  WHERE
    fcc.channel IN ('chat', 'call', 'email')
)
SELECT DISTINCT
  sk_ticket,
  channel,
  department AS queue,
  journey AS step,
  customer_type AS client,
  motivation,
  theme,
  theme_detail,
  sub_journey AS area,
  email,
  ts_created,
  YEAR(CURRENT_DATE - 1) AS year,
  MONTH(CURRENT_DATE - 1) AS month,
  DAY(CURRENT_DATE - 1) AS day,
  NOW() AS ts_load
FROM
  base
WHERE
  agent_organization IN ('webhelp')
  AND front_or_back = 'front'
  AND DATE_TRUNC('month', ts_created) BETWEEN DATE_TRUNC('month',DATE('{load_start_date}')) - INTERVAL '6' MONTH AND DATE('{load_end_date}')
