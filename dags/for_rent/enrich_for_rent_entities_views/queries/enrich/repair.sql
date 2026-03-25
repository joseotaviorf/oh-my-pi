WITH ongoing_repair AS (
    SELECT
        rr.id AS id_entity,
        rr.id_house,
        rr.id_contract,
        'FR_REPAIR_ONGOING' AS entity,
        'RENT' AS business_context,
        TO_JSON(
            STRUCT(
                rr.status AS status,
                rr.ts_created AS when
            )
        ) AS properties,
        CASE
            WHEN rr.status IN ('AWAITING_BUDGET', 'AWAITING_BUDGET_APPROVAL', 'AWAITING_OWNER_ACTION', 'BUDGETING_IN_PROGRESS', 'COMPULSORY', 'IN_EXECUTION', 'IN_NEGOTIATION', 'IN_PROGRESS', 'REQUESTED', 'TENANT_NEEDS_CX_HELP', 'NULL') THEN TRUE
            WHEN rr.status IN ('FINISHED', 'RESOLVED', 'CANCELED') THEN FALSE
            ELSE NULL
        END AS is_active,
        rr.ts_created,
        rr.ts_updated
    FROM
        datalake_repairs_clean.repair_request AS rr
    WHERE
        rr.year >= 2025
        AND rr.status IS NOT NULL
),
offboarding_repair AS (
    SELECT
        rr.id_repair_request AS id_entity,
        ins.id_contract,
        ins.id_inspector,
        'FR_REPAIR_OFFBOARDING' AS entity,
        'RENT' AS business_context,
        TO_JSON(
            STRUCT(
                rr.ts_created AS when
            )
        ) AS properties,
        IF(rr.is_finished = TRUE, FALSE, TRUE) AS is_active,
        rr.ts_created,
        rr.ts_updated
    FROM
        datalake_inspection_services_clean.repair_request AS rr
    LEFT JOIN
        datalake_inspection_services_clean.item_group AS ig
            ON rr.id_item_group = ig.id_item_group
    LEFT JOIN
        datalake_inspection_services_clean.room AS ro
            ON ro.id_room = ig.id_room
    LEFT JOIN
        datalake_inspection_services_clean.assessment AS asm
            ON asm.id_assessment = ro.id_assessment
    LEFT JOIN
        datalake_inspection_services_clean.inspection AS ins
            ON ins.id_inspection = asm.id_inspection
    WHERE
        rr.year >= 2025
),
union_all AS (
    SELECT
        id_entity,
        id_house,
        id_contract,
        CAST(NULL AS STRING) AS id_inspector,
        entity,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        ongoing_repair
    UNION ALL
    SELECT
        id_entity,
        CAST(NULL AS BIGINT) AS id_house,
        id_contract,
        id_inspector,
        entity,
        business_context,
        properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        offboarding_repair
),
personas_base AS (
    SELECT
        ua.id_entity,
        COALESCE(ua.id_house, c.id_house) AS id_house,
        ua.id_contract,
        c.id_tenant,
        c.id_owner,
        ua.id_inspector,
        ua.entity,
        ua.business_context,
        ua.properties,
        ua.is_active,
        ua.ts_created,
        ua.ts_updated
    FROM
        union_all AS ua
    JOIN
        core_contract.contract AS c
            ON ua.id_contract = c.id_contract
)
SELECT
    pb.id_entity,
    pb.id_house,
    pb.id_contract,
    pb.id_owner AS id_user,
    pb.entity,
    'OWNER' AS persona,
    pb.business_context,
    pb.properties,
    pb.is_active,
    pb.ts_created,
    pb.ts_updated
FROM
    personas_base AS pb
UNION ALL
SELECT
    pb.id_entity,
    pb.id_house,
    pb.id_contract,
    pb.id_tenant AS id_user,
    pb.entity,
    'TENANT' AS persona,
    pb.business_context,
    pb.properties,
    pb.is_active,
    pb.ts_created,
    pb.ts_updated
FROM
    personas_base AS pb
UNION ALL
SELECT
    pb.id_entity,
    pb.id_house,
    pb.id_contract,
    pb.id_inspector AS id_user,
    pb.entity,
    'AGENT_INSPECTOR' AS persona,
    pb.business_context,
    pb.properties,
    pb.is_active,
    pb.ts_created,
    pb.ts_updated
FROM
    personas_base AS pb
WHERE
    entity = 'FR_REPAIR_OFFBOARDING'
