WITH base AS (
  SELECT
    NULLIF(frc.sk_ticket, -1) AS sk_ticket,
    frc.channel,
    frc.ts_created,
    dd.department,
    dd.front_or_back,
    dt.customer_type_tag AS customer_type,
    dt.motivation,
    dt.theme,
    dt.theme_detail,
    dt.journey,
    dt.sub_journey,
    CASE
      WHEN da.agent_organization = 'atn' THEN 'atento'
      WHEN da.agent_organization = 'atento' THEN 'atento'
      WHEN da.agent_organization = 'webhelp' THEN 'webhelp'
      WHEN da.agent_organization = 'webhelpbr' THEN 'webhelp'
      WHEN da.agent_organization = 'quintoandar.com' THEN 'quintoandar'
      WHEN da.agent_organization = 'quintoandar' THEN 'quintoandar'
      WHEN da.agent_organization = 'contractors' THEN 'webhelp'
      ELSE da.agent_organization
    END AS agent_organization,
    da.email
  FROM
    dw_customer_support.fact_received_contact AS frc
  LEFT JOIN
    dw_customer_support.dim_department AS dd
      ON dd.sk_department = frc.sk_department
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON dt.sk_taxonomy = frc.sk_taxonomy
  LEFT JOIN
    dw_customer_support.dim_agent AS da
      ON da.email = frc.agent_email
  WHERE
    frc.channel IN ('chat', 'call', 'email')
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
  YEAR(ts_created) AS year,
  MONTH(ts_created) AS month,
  DAY(ts_created) AS day,
  NOW() AS ts_load
FROM
  base
WHERE
  agent_organization IN ('atento')
  AND front_or_back = 'front'
  AND DATE_TRUNC('month', ts_created) BETWEEN DATE_TRUNC('month', DATE('{load_start_date}')) - INTERVAL '6' MONTH AND DATE('{load_end_date}')