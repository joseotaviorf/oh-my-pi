SELECT
    rr.id AS id_entity,
    COALESCE(rr.id_house, c.id_house) AS id_house,
    rr.id_contract,
    c.id_tenant,
    c.id_owner,
    'FR_ONGOING_REPAIR' AS entity,
    'RENT' AS business_context,
    rr.status,
    CASE
        WHEN rr.status IN ('AWAITING_BUDGET', 'AWAITING_BUDGET_APPROVAL', 'AWAITING_OWNER_ACTION', 'BUDGETING_IN_PROGRESS', 'COMPULSORY', 'IN_EXECUTION', 'IN_NEGOTIATION', 'IN_PROGRESS', 'REQUESTED', 'TENANT_NEEDS_CX_HELP', 'NULL') THEN TRUE
        WHEN rr.status IN ('FINISHED', 'RESOLVED', 'CANCELED') THEN FALSE
        ELSE NULL
    END AS is_active,
    rr.ts_created,
    rr.ts_updated
FROM
    datalake_repairs_test_clean.repair_request AS rr
JOIN
    core_contract.contract AS c
        ON rr.id_contract = c.id_contract