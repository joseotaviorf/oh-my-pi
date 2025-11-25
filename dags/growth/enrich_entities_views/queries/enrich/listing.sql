WITH last_contract AS (
    SELECT
        id_house,
        id_contract
    FROM
        core_contract.contract
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_house ORDER BY ts_created DESC) = 1
),
listing_base AS (
    SELECT
        lbc.id AS id_entity,
        lbc.id_house,
        IF(lbc.business_context = 'RENT', c.id_contract, NULL) AS id_contract,
        h.id_user AS id_owner,
        'LISTING' AS entity,
        lbc.business_context,
        TO_JSON(
            STRUCT(
                lbc.status AS status,
                lbc.ts_created AS when
            )
        ) AS properties,
        CASE
            WHEN lbc.status IN ('PUBLISHED', 'EDITING')
                OR (lbc.status = 'SUSPENDED'
                    AND lbc.status_reason NOT IN ('OWNER_GAVE_UP_RENTING', 'OwnerConsequencesManagement', 'OwnerReforming', 'OwnerTemporarilySuspended', 'OwnerTraveling')) THEN TRUE
            WHEN lbc.status IN ('OPTED_OUT', 'UNPUBLISHED')
                OR (lbc.status = 'SUSPENDED'
                    AND lbc.status_reason IN ('OWNER_GAVE_UP_RENTING', 'OwnerConsequencesManagement', 'OwnerReforming', 'OwnerTemporarilySuspended', 'OwnerTraveling')) THEN FALSE
            ELSE NULL
        END AS is_active,
        lbc.ts_created,
        lbc.ts_updated
    FROM
        datalake_ebdb_clean.listing_business_context AS lbc
    LEFT JOIN
        datalake_ebdb_clean.house AS h
            ON h.id = lbc.id_house
    LEFT JOIN
        last_contract AS c
            ON c.id_house = lbc.id_house
)
SELECT
    lb.id_entity,
    lb.id_house,
    lb.id_contract,
    lb.id_owner AS id_user,
    lb.entity,
    'OWNER' AS persona,
    lb.business_context,
    lb.properties,
    lb.is_active,
    lb.ts_created,
    lb.ts_updated
FROM
    listing_base AS lb
