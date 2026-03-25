WITH termination_base AS (
    SELECT
        id AS id_entity,
        id_contract,
        'FR_TERMINATION' AS entity,
        'RENT' AS business_context,
        TO_JSON(
            STRUCT(
                status AS status,
                ts_created AS when
            )
        ) AS properties,
        CASE
            WHEN status IN ('DONE', 'CANCELED') THEN FALSE
            WHEN status IN (
                'REQUESTED',
                'INSPECTION_UNDER_REVIEW',
                'INSPECTION_SCHEDULED',
                'INSPECTION_OPTED_OUT',
                'INSPECTION_EXECUTED',
                'INSPECTION_CANCELED'
            ) THEN TRUE
            ELSE NULL
        END AS is_active,
        ts_created,
        ts_updated
    FROM
        datalake_terminator_clean.termination
)
SELECT
    tb.id_entity,
    c.id_house,
    c.id_contract AS id_contract,
    c.id_owner AS id_user,
    tb.entity,
    'OWNER' AS persona,
    tb.business_context,
    tb.properties,
    tb.is_active,
    tb.ts_created,
    tb.ts_updated
FROM
    termination_base AS tb
INNER JOIN
    core_contract.contract AS c
        ON tb.id_contract = c.id_contract
UNION ALL
SELECT
    tb.id_entity,
    c.id_house,
    c.id_contract AS id_contract,
    c.id_tenant AS id_user,
    tb.entity,
    'TENANT' AS persona,
    tb.business_context,
    tb.properties,
    tb.is_active,
    tb.ts_created,
    tb.ts_updated
FROM
    termination_base AS tb
INNER JOIN
    core_contract.contract AS c
        ON tb.id_contract = c.id_contract
