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
        CONCAT(lbc.id_house, '_', lbc.business_context) AS id_entity,
        lbc.id_house,
        IF(lbc.business_context = 'RENT', c.id_contract, NULL) AS id_contract,
        COALESCE(u.id, h.id_user) AS id_owner,
        'LISTING' AS entity,
        lbc.business_context,
        TO_JSON(
            STRUCT(
                lbc.status AS status,
                lbc.ts_created AS when
            )
        ) AS properties,
        CASE
            WHEN lbc.status IN ('PUBLISHED', 'EDITING') THEN TRUE
            WHEN lbc.status IN ('OPTED_OUT', 'UNPUBLISHED', 'SUSPENDED') THEN FALSE
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
        datalake_ebdb_clean.house_listing_relation AS hl
            ON hl.id_house = lbc.id_house
            AND hl.related_as = 'PROPERTY_OWNER'
    LEFT JOIN
        datalake_ebdb_clean.user AS u
            ON u.id = hl.id_related
            OR u.uuid_person = hl.id_related
    LEFT JOIN
        last_contract AS c
            ON c.id_house = lbc.id_house
)
SELECT DISTINCT
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
