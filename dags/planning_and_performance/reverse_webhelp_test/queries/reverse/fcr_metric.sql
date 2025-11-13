SELECT DISTINCT
  ft.sk_ticket,
  ft.sk_last_analyst AS sk_agent,
  ft.sk_session AS sk_main_session,
  ft.channel,
  dd.department AS main_department,
  ft.direction,
  dd.area,
  dd.department,
  dd.journey_step,
  dd.board,
  ft.front_or_back,
  dd.team,
  CONCAT('https://quintoandar.zendesk.com/agent/tickets/', ft.sk_ticket) AS external_url,
  da.full_name AS agent_full_name,
  da.email AS agent_email,
  da.agent_organization,
  dd.is_active,
  NULL AS is_ticket_session,
  NULL AS is_fcr_customer,
  NULL AS is_recontact,
  ft.ts_created AS ts_started,
  NULL AS ts_survey,
  ft.ts_solved,
  ft.ts_closed,
  YEAR(CURRENT_DATE - 1) AS year,
  MONTH(CURRENT_DATE - 1) AS month,
  DAY(CURRENT_DATE - 1) AS day,
  NOW() AS ts_load
FROM
  dw_customer_support.fact_tickets AS ft
LEFT JOIN
  dw_customer_support.dim_department AS dd
    ON ft.sk_main_department = dd.sk_department
LEFT JOIN
  dw_customer_support.dim_analyst AS da
    ON ft.sk_last_analyst = da.sk_analyst
WHERE
  DATE(ft.ts_created) BETWEEN DATE('{load_start_date}') - INTERVAL '1' YEAR AND DATE('{load_end_date}')
  AND da.agent_organization IN ('webhelp', 'webhelpbr')
  AND (ft.front_or_back IS NULL OR ft.front_or_back <> 'back')
  AND dd.area = 'CX'
  AND ft.direction = 'inbound'
