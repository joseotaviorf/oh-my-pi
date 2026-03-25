WITH inspection_base AS (
    SELECT
        ib.id AS id_entity,
        ib.id_contract,
        ib.id_house,
        ib.id_user_inspector,
        c.id_owner,
        c.id_tenant,
        'FR_INSPECTION' AS entity,
        'RENT' AS business_context,
        TO_JSON(
            STRUCT(
                ib.status AS status,
                COALESCE(ib.dt_inspected, b.dt_booking) AS when
            )
        ) AS properties,
        CASE
            WHEN ib.status IN ('Finalizada', 'Cancelada', 'ContratoCancelado', 'Revisada') THEN FALSE
            WHEN ib.status IN ('Agendada', 'Comentada', 'EmAcordo', 'EmRevisao', 'Nova') THEN TRUE
            ELSE NULL
        END AS is_active,
        ib.ts_created,
        ib.ts_updated
    FROM
        datalake_ebdb_clean.inspection AS ib
    INNER JOIN
        core_contract.contract AS c
            ON ib.id_contract = c.id_contract
    LEFT JOIN
        datalake_ebdb_clean.booking AS b
            ON b.id = ib.id_booking
    WHERE
        YEAR(ib.ts_created) >= 2025
)
SELECT
    ib.id_entity,
    ib.id_house,
    ib.id_contract,
    ib.id_owner AS id_user,
    ib.entity,
    'OWNER' AS persona,
    ib.business_context,
    ib.properties,
    ib.is_active,
    ib.ts_created,
    ib.ts_updated
FROM
    inspection_base AS ib
UNION ALL
SELECT
    ib.id_entity,
    ib.id_house,
    ib.id_contract,
    ib.id_tenant AS id_user,
    ib.entity,
    'TENANT' AS persona,
    ib.business_context,
    ib.properties,
    ib.is_active,
    ib.ts_created,
    ib.ts_updated
FROM
    inspection_base AS ib
UNION ALL
SELECT
    ib.id_entity,
    ib.id_house,
    ib.id_contract,
    ib.id_user_inspector AS id_user,
    ib.entity,
    'AGENT_INSPECTOR' AS persona,
    ib.business_context,
    ib.properties,
    ib.is_active,
    ib.ts_created,
    ib.ts_updated
FROM
    inspection_base AS ib
