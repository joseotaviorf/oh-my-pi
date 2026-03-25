WITH contract_base AS (
    SELECT
        id_contract AS id_entity,
        id_house,
        id_contract,
        id_owner,
        id_tenant,
        'FR_CONTRACT' AS entity,
        'RENT' AS business_context,
        TO_JSON(
            STRUCT(
                status AS status,
                dt_started AS when
            )
        ) AS properties,
        CASE
            WHEN status IN ('Cancelado', 'Finalizado') THEN FALSE
            WHEN status IN ('Ativo', 'Minuta', 'PreAssinaturas') THEN TRUE
            ELSE NULL
        END AS is_active,
        ts_signed,
        ts_created,
        ts_updated
    FROM
        core_contract.contract
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
    contract_base
UNION ALL
SELECT
    id_entity,
    id_house,
    id_contract,
    id_tenant AS id_user,
    entity,
    CASE
        WHEN ts_signed IS NOT NULL THEN 'TENANT'
        ELSE 'TENANT_PROSPECT'
    END AS persona,
    business_context,
    properties,
    is_active,
    ts_created,
    ts_updated
FROM
    contract_base
