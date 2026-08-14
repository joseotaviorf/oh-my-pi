-- Resolves the PROPERTY_OWNER relation to a user id. `hl.id_related` is a STRING holding
-- either a numeric `user.id` or a `user.uuid_person`, so the original wrote this as one join
-- with a disjunctive predicate:
--     ON u.id = hl.id_related OR u.uuid_person = hl.id_related
-- An OR across two different columns is not an equi-join, so Spark has no hash-join option
-- and plans a BroadcastNestedLoopJoin over the whole `user` table. Views are inlined at
-- planning time, so that nested loop lands inside every query reading this view.
--
-- UNION (not UNION ALL) reproduces OR semantics exactly: one `user` row matching both
-- predicates contributes one row, while two distinct users matching one predicate each still
-- contribute two. Same rewrite as enrich_entities_views (#27637).
--
-- NOTE: the `hl.id = pj.id_house` join below is preserved verbatim. Every other view joins
-- `hl.id_house`, so this looks like a pre-existing bug, but changing it would alter results
-- and is out of scope here.
WITH owner_resolved AS (
    SELECT
        hl.id AS id_relation,
        u.id AS id_owner
    FROM
        datalake_ebdb_clean.house_listing_relation AS hl
    INNER JOIN
        datalake_ebdb_clean.user AS u
            ON u.id = hl.id_related
    WHERE
        hl.related_as = 'PROPERTY_OWNER'

    UNION

    SELECT
        hl.id AS id_relation,
        u.id AS id_owner
    FROM
        datalake_ebdb_clean.house_listing_relation AS hl
    INNER JOIN
        datalake_ebdb_clean.user AS u
            ON u.uuid_person = hl.id_related
    WHERE
        hl.related_as = 'PROPERTY_OWNER'
),
photo_session_exploded AS (
    SELECT DISTINCT
        pj.id AS id_entity,
        pj.id_house,
        uu.id AS id_photographer,
        'PHOTO_SESSION' AS entity,
        COALESCE(u.id_owner, h.id_user) AS id_owner,
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
        owner_resolved AS u
            ON u.id_relation = hl.id
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
