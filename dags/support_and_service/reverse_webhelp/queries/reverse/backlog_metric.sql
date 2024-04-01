SELECT DISTINCT
    bmt.sk_task AS sk_ticket,
    bmt.sk_agent,
    bmt.origin AS channel,
    bmt.status,
    da.agent_organization,
    da.email AS agent_email,
    dd.department,
    dd.front_or_back,
    dt.motivation AS contact_motivation_tag,
    dt.theme_detail AS contact_theme_detail_tag,
    dt.customer_type_tag AS customer_type_tag,
    dtt.tags AS tag,
    dt.step_tag AS step_tag,
    dd.team,
    dd.journey_step,
    dd.area,
    bmt.sla_target,
    bmt.days_worked,
    bmt.days_worked_with_days_offs,
    bmt.days_off,
    bmt.is_daily_backlog,
    bmt.is_backlog_within_sla AS is_backlog_in_time,
    bmt.is_backlog_with_exceed_sla AS is_backlog_not_in_time,
    bmt.dt_metric_reference,
    bmt.ts_started,
    bmt.ts_solved,
    tf.replies,
    dti.ticket_via,
    YEAR(CURRENT_DATE - 1) AS year,
    MONTH(CURRENT_DATE - 1) AS month,
    DAY(CURRENT_DATE - 1) AS day,
    NOW() AS ts_load 
FROM
    dw_customer_support.fact_backlog_metrics_tasks AS bmt
LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
        ON bmt.sk_taxonomy = dt.sk_taxonomy
LEFT JOIN
    dw_customer_support.dim_ticket_tags AS dtt
        ON bmt.sk_tags = dtt.sk_tags
LEFT JOIN
    dw_customer_support.dim_department AS dd
        ON bmt.sk_main_department = dd.sk_department
LEFT JOIN
    dw_customer_support.dim_agent AS da
        ON bmt.sk_agent = da.sk_agent
LEFT JOIN 
    dw_customer_support.fact_ticket AS tf
        ON tf.sk_ticket = bmt.sk_task
LEFT JOIN 
    dw_tickets.dim_ticket AS dti
        ON dti.sk_ticket = bmt.sk_task

WHERE
    DATE(bmt.dt_metric_reference) >= '2022-07-19'
    AND dd.is_partner IS TRUE
    AND dd.front_or_back <> 'front'
    AND da.agent_organization IN ('webhelp', 'webhelpbr')