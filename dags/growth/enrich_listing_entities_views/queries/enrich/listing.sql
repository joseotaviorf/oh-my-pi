-- QUALIFY is Databricks-only; EMR Spark 3.5 cannot parse it. Rewritten as a ranked CTE plus
-- a WHERE filter, matching the equivalent CTEs in enrich_entities_views/listing.sql.
WITH contract_ranked AS (
    SELECT
        id_house,
        id_contract,
        ROW_NUMBER() OVER (
            PARTITION BY id_house
            ORDER BY ts_created DESC
        ) AS contract_rank
    FROM
        core_contract.contract
),
last_contract AS (
    SELECT
        id_house,
        id_contract
    FROM
        contract_ranked
    WHERE
        contract_rank = 1
),
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
owner_resolved AS (
    SELECT
        hl.id_house,
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
        hl.id_house,
        u.id AS id_owner
    FROM
        datalake_ebdb_clean.house_listing_relation AS hl
    INNER JOIN
        datalake_ebdb_clean.user AS u
            ON u.uuid_person = hl.id_related
    WHERE
        hl.related_as = 'PROPERTY_OWNER'
),
listing_base AS (
    SELECT
        CONCAT(lbc.id_house, '_', lbc.business_context) AS id_entity,
        lbc.id_house,
        IF(lbc.business_context = 'RENT', c.id_contract, NULL) AS id_contract,
        COALESCE(u.id_owner, h.id_user) AS id_owner,
        'LISTING' AS entity,
        lbc.business_context,
        TO_JSON(
            STRUCT(
                CASE
                    WHEN lbc.status = 'OPTED_OUT' AND lbc.status_reason IS NULL THEN 'EXCLUDED'
                    WHEN lbc.status = 'SUSPENDED' AND lbc.status_reason = 'RENTED' THEN 'CONTRACT_ONGOING'
                    WHEN lbc.status = 'SUSPENDED'
                        AND lbc.status_reason IN ('ContractDraft', 'HouseReserved', 'PaidGuarantee', 'RENTAL_GUARANTEE', 'ProposalDocumentationApproved', 'ProposalDocumentationSentToCardiff', 'CCV_SIGNED') THEN 'ADVANCED_OFFER'
                    ELSE lbc.status
                END AS status,
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
        owner_resolved AS u
            ON u.id_house = lbc.id_house
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
