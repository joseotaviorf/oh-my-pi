SELECT DISTINCT
    id_transition,
    id_workflow,
    id_task_from,
    task_from.type AS origin_type,
    id_task_to,
    task_to.type AS destination_type,
    status,
    CASE
        WHEN release_minuta IS NOT NULL THEN 'Release Minuta'
        WHEN owner_pendency IS NOT NULL THEN 'Solve Owner Pendency'
        WHEN tenant_pendency IS NOT NULL THEN 'Solve Tenant Pendency'
        WHEN reject_proposal IS NOT NULL THEN 'Reject Proposal'
    END AS conclusion_option,
    CASE
        WHEN release_minuta IS NOT NULL THEN ARRAY_JOIN(FROM_JSON(COALESCE(release_minuta,'[]'), 'ARRAY<STRING>'), ",")
        WHEN owner_pendency IS NOT NULL THEN ARRAY_JOIN(FROM_JSON(COALESCE(owner_pendency,'[]'), 'ARRAY<STRING>'), ",")
        WHEN tenant_pendency IS NOT NULL THEN ARRAY_JOIN(FROM_JSON(COALESCE(tenant_pendency,'[]'), 'ARRAY<STRING>'), ",")
        WHEN reject_proposal IS NOT NULL THEN ARRAY_JOIN(FROM_JSON(COALESCE(reject_proposal,'[]'), 'ARRAY<STRING>'), ",")
    END AS conclusion_context,
    context,
    CASE
        WHEN owner_contact_channel IS NOT NULL THEN owner_contact_channel
        WHEN frontend_contact_channel IS NOT NULL THEN frontend_contact_channel
        WHEN tenant_contact_channel IS NOT NULL THEN tenant_contact_channel
    END AS contact_channel,
    ts_transitioned
FROM 
    datalake_crm.workflows_transitions AS wt
INNER JOIN
    datalake_crm.tasks AS task_from
        ON wt.id_task_from = task_from.id
INNER JOIN
    datalake_crm.tasks AS task_to
        ON wt.id_task_to = task_to.id
