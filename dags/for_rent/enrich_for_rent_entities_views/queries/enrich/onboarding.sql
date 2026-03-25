WITH onboarding_base AS (
    SELECT
        ob.id AS id_entity,
        ct.id_house,
        ob.id_contrato AS id_contract,
        ct.id_owner,
        ct.id_tenant,
        'FR_ONBOARDING' AS entity,
        'RENT' AS business_context,
        TO_JSON(
            STRUCT(
                ob.status AS status,
                ob.ts_created AS when
            )
        ) AS properties,
        CASE
            WHEN ob.status IN ('Finished', 'Aborted') THEN FALSE
            ELSE TRUE
        END AS is_active,
        ob.ts_created,
        ob.ts_updated
    FROM
        datalake_ebdb_clean.onboarding AS ob
    LEFT JOIN
        core_contract.contract AS ct
            ON ob.id_contrato = ct.id_contract
    WHERE
        YEAR(ob.ts_created) >= 2025
)
SELECT
    id_entity,
    id_house,
    id_contract,
    id_owner AS id_user,
    entity,
    'OWNER' AS persona,
    business_context,
    properties,
    is_active,
    ts_created,
    ts_updated
FROM
    onboarding_base
UNION ALL
SELECT
    id_entity,
    id_house,
    id_contract,
    id_tenant AS id_user,
    entity,
    'TENANT' AS persona,
    business_context,
    properties,
    is_active,
    ts_created,
    ts_updated
FROM
    onboarding_base
