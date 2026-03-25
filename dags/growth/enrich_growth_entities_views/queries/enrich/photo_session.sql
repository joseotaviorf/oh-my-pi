WITH photo_session_exploded AS (
    SELECT DISTINCT
        pj.id AS id_entity,
        pj.id_house,
        uu.id AS id_photographer,
        'PHOTO_SESSION' AS entity,
        COALESCE(u.id, h.id_user) AS id_owner,
        NULL AS business_context,
        pj.status AS status,
        CASE
            WHEN UPPER(TRIM(pj.status)) IN ('PUBLICADO', 'CANCELADO', 'COMPLETADO', 'FOTOSTIRADAS') THEN FALSE
            ELSE TRUE
        END AS is_active,
        pj.ts_created,
        pj.ts_updated
    FROM
        datalake_ebdb_clean.photographer_job AS pj
    LEFT JOIN
        datalake_ebdb_clean.house_listing_relation AS hl
            ON hl.id = pj.id_house
            AND hl.related_as = 'PROPERTY_OWNER'
    LEFT JOIN
        datalake_ebdb_clean.user AS u
            ON u.id = hl.id_related
            OR u.uuid_person = hl.id_related
    LEFT JOIN
        datalake_ebdb_clean.house AS h
            ON pj.id_house = h.id
    LEFT JOIN
        datalake_ebdb_clean.user AS uu
            ON pj.id_photographer_data = uu.id_photographer_data
    WHERE
        YEAR(pj.ts_created) >= 2025
),
photo_session_base AS (
    SELECT
        id_entity,
        id_house,
        CAST(NULL AS STRING) AS id_contract,
        id_owner,
        id_photographer,
        entity,
        business_context,
        TO_JSON(
            STRUCT(
                status AS status,
                ts_created AS when
            )
        ) AS properties,
        is_active,
        ts_created,
        ts_updated
    FROM
        photo_session_exploded
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
    photo_session_base
WHERE
    id_owner IS NOT NULL
UNION ALL
SELECT
    id_entity,
    id_house,
    id_contract,
    id_photographer AS id_user,
    entity,
    'AGENT_PHOTOGRAPHER' AS persona,
    business_context,
    properties,
    is_active,
    ts_created,
    ts_updated
FROM
    photo_session_base
WHERE
    id_photographer IS NOT NULL
