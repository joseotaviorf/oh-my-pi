SELECT
    id_listing_quality_sla,
    business_key,
    id_ticket,
    id_house,
    agent_organization,
    has_demand,
    has_task_done,
    has_sla_achieved,
    has_backlog,
    has_video,
    dt_uploaded,
    dt_ticket_created,
    dt_ticket_solved,
    YEAR(CURRENT_DATE - 1) AS year,
    MONTH(CURRENT_DATE - 1) AS month,
    DAY(CURRENT_DATE - 1) AS day,
    NOW() AS ts_load
FROM
    datalake_listing_jobs.listing_quality_sla
WHERE
    agent_organization IN ('webhelp', 'webhelpbr')

