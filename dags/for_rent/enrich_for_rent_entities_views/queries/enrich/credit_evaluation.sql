WITH credit_evaluation_base AS (
    SELECT
        ce.id_credit_evaluation AS id_entity,
        ce.id_house,
        CAST(NULL AS BIGINT) AS id_contract,
        ce.id_user,
        ce.id_owner,
        'FR_CREDIT_EVALUATION' AS entity,
        'RENT' AS business_context,
        TO_JSON(
            STRUCT(
                ce.status AS status,
                ce.ts_created AS when
            )
        ) AS properties,
        CASE
            WHEN ce.status IN ('NOT_SENT', 'ON_HOLD', 'PROCESSING') THEN TRUE
            WHEN ce.status IN ('CANCELLED', 'FAILED', 'FINISHED') THEN FALSE
            ELSE NULL
        END AS is_active,
        ce.ts_created,
        ce.ts_updated
    FROM
        core_credit_evaluation.credit_evaluation AS ce
)
SELECT
    ce.id_entity,
    ce.id_house,
    ce.id_contract,
    ce.id_owner AS id_user,
    ce.entity,
    'OWNER' AS persona,
    ce.business_context,
    ce.properties,
    ce.is_active,
    ce.ts_created,
    ce.ts_updated
FROM
    credit_evaluation_base AS ce
UNION ALL
SELECT
    ce.id_entity,
    ce.id_house,
    ce.id_contract,
    ce.id_user,
    ce.entity,
    'TENANT_PROSPECT' AS persona,
    ce.business_context,
    ce.properties,
    ce.is_active,
    ce.ts_created,
    ce.ts_updated
FROM
    credit_evaluation_base AS ce
