SELECT DISTINCT
    ft.sk_ticket,
    ft.sk_last_agent AS sk_agent,
    ft.sk_main_session,
    ft.channel,
    ft.main_department,
    dc.direction,
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
    ft.is_ticket_session,
    ft.is_fcr_customer,
    ft.is_recontact,
    ft.ts_started,
    ft.ts_survey,
    ft.ts_solved,
    ft.ts_closed,
    YEAR(CURRENT_DATE - 1) AS year,
    MONTH(CURRENT_DATE - 1) AS month,
    DAY(CURRENT_DATE - 1) AS day,
    NOW() AS ts_load
FROM
    dw_customer_support.fact_ticket AS ft
LEFT JOIN
    dw_customer_support.dim_channel AS dc
      ON ft.sk_channel = dc.sk_channel
LEFT JOIN
    dw_customer_support.dim_department AS dd
      ON ft.sk_main_department = dd.sk_department
LEFT JOIN
    dw_customer_support.dim_agent AS da
      ON ft.sk_last_agent = da.sk_agent
WHERE
    DATE(ft.ts_started) >= '2022-07-19'
    AND da.agent_organization IN ('webhelp', 'webhelpbr')
    AND (ft.front_or_back IS NULL OR ft.front_or_back <> 'back')
    AND dd.area = 'CX'
    AND dc.direction = 'inbound'
