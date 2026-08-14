-- Resolves the PROPERTY_OWNER relation to a user id. `hl.id_related` is a STRING holding
-- either a numeric `user.id` or a `user.uuid_person`, so the original wrote this as one join
-- with a disjunctive predicate:
--     ON (u.id = hl.id_related OR u.uuid_person = hl.id_related)
-- An OR across two different columns is not an equi-join, so Spark has no hash-join option
-- and plans a BroadcastNestedLoopJoin over the whole `user` table. Views are inlined at
-- planning time, so that nested loop lands inside every query reading this view.
--
-- UNION (not UNION ALL) reproduces OR semantics exactly: one `user` row matching both
-- predicates contributes one row, while two distinct users matching one predicate each still
-- contribute two. Same rewrite as enrich_entities_views (#27637).
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
reservation_base AS (
    SELECT
        rv.id AS id_entity,
        rv.id_house,
        rv.id_tenant,
        COALESCE(u.id_owner, h.id_user) AS id_owner,
        CAST(NULL AS BIGINT) AS id_contract,
        'FR_RESERVATION' AS entity,
        'RENT' AS business_context,
        TO_JSON(
            STRUCT(
                rv.status AS status,
                rv.ts_created AS when
            )
        ) AS properties,
        IF(rv.is_ongoing = TRUE, TRUE, FALSE) AS is_active,
        rv.ts_created,
        rv.ts_updated
    FROM
        datalake_kill_queue_clean.reservation AS rv
    LEFT JOIN
        datalake_ebdb_clean.house AS h
            ON h.id = rv.id_house
    LEFT JOIN
        datalake_ebdb_clean.house_listing_relation AS hl
            ON hl.id = rv.id_house
            AND hl.related_as = 'PROPERTY_OWNER'
    LEFT JOIN
        owner_resolved AS u
            ON u.id_relation = hl.id
)
SELECT
    rb.id_entity,
    rb.id_house,
    rb.id_contract,
    rb.id_tenant AS id_user,
    rb.entity,
    'TENANT_PROSPECT' AS persona,
    rb.business_context,
    rb.properties,
    rb.is_active,
    rb.ts_created,
    rb.ts_updated
FROM
    reservation_base AS rb
UNION ALL
SELECT
    rb.id_entity,
    rb.id_house,
    rb.id_contract,
    rb.id_owner AS id_user,
    rb.entity,
    'OWNER' AS persona,
    rb.business_context,
    rb.properties,
    rb.is_active,
    rb.ts_created,
    rb.ts_updated
FROM
    reservation_base AS rb
