SELECT
    c.id AS id_capability,
    c.id_agent,
    c.type,
    c.status,
    cs.business_context,
    cs.is_passive_lead_receiver,
    c.ts_created,
    c.ts_updated
FROM
    datalake_ebdb_clean.capability AS c
LEFT JOIN
    datalake_ebdb_clean.demand_visit_management_capability_settings AS cs
        ON c.id = cs.id_capability
