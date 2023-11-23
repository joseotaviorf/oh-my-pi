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
    dt_ticket_solved
FROM
    datalake_listing_jobs.listing_quality_sla
WHERE
    agent_organization = "webhelp"
