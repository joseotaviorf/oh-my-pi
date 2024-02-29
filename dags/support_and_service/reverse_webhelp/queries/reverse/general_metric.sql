SELECT DISTINCT
    ft.sk_ticket,
    ft.sk_last_agent AS sk_agent,
    ft.channel,
    ft.first_csat_score AS csat_score,
    ft.status,
    CASE
        WHEN ft.csat_score BETWEEN 4 AND 5 THEN 'Satisfied'
        WHEN ft.csat_score = 3 THEN 'Neutral'
        WHEN ft.csat_score BETWEEN 1 AND 2 THEN 'Dissatisfied'
        ELSE NULL
    END AS csat_type,
    ft.first_csat_comment AS csat_comment,
    ft.main_department,
    dc.direction,
    dd.area,
    dd.department,
    dd.journey_step,
    ft.front_or_back,
    dd.team,
    dt.motivation AS contact_motivation_tag,
    dt.theme_detail AS contact_theme_detail_tag,
    dt.customer_type_tag,
    dtt.tags AS tag,
    dt.step_tag,
    CONCAT('https://quintoandar.zendesk.com/agent/tickets/', ft.sk_ticket) AS external_url,
    ROUND(CAST(ft.full_resolution_time/60.0 AS DOUBLE), 2) AS hours_to_solve_ticket,
    da.full_name AS agent_full_name,
    da.email AS agent_email,
    da.agent_organization,
    ft.reopens,
    ft.replies,
    dd.is_active,
    ft.has_answered_csat,
    ft.has_transfers,
    ft.resolution_survey AS is_resolution,
    ft.ts_started,
    ft.ts_survey,
    ft.ts_csat_first_response AS ts_csat_response,
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
    dw_customer_support.dim_ticket_tags AS dtt
        ON ft.sk_tags = dtt.sk_tags
LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
        ON ft.sk_taxonomy = dt.sk_taxonomy
LEFT JOIN
    dw_customer_support.dim_agent AS da
        ON ft.sk_last_agent = da.sk_agent
WHERE
    DATE(ft.ts_started) >= DATE('2022-01-01')
    AND dd.is_partner IS TRUE
    AND dd.front_or_back <> 'front'
    AND da.agent_organization IN ('webhelp', 'webhelpbr')
