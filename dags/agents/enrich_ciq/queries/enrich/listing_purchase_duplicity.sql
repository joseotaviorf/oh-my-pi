WITH atlas_house_deduplication AS (
    SELECT 
        dep.id_duplicity,
        dep.id_house,
        dep.action_type,
        dep.duplicity_reason,
        dep.is_same_property_owner,
        dep.ts_action,
        dep.ts_created,
        dep.ts_updated
    FROM
        datalake_listing_deduplication.atlas_house_deduplication AS dep
    WHERE
        dep.is_last_duplicity IS TRUE
),
ciq_listing_purchase AS (
    SELECT
        clp.id_listing_purchase,
        clp.id_house,
        clp.id_house_listing,
        clp.id_ciq_user,
        clp.id_owner,
        clp.id_house,
        clp.id_ciq_user,
        clp.id_owner,
        clp.id_contract,
        clp.id_accounting_entry,
        clp.id_address_parsed_duplicity,
        atlas.id_duplicity AS id_atlas_duplicity,
        clp.parsed_first_listing_order,
        clp.listing_status,
        clp.consultant_type,
        clp.business_context,
        atlas.action_type AS atlas_duplicity_action,
        atlas.duplicity_reason AS atlas_duplicity_reason,
        clp.total_days_since_house_inactived,
        clp.has_republication,
        clp.is_last_contract_signed_by_house,
        clp.is_house_inactive,
        clp.is_last_house_listing,
        atlas.id_house IS NOT NULL AS is_atlas_atlas_duplicity,
        atlas.action_type = "BLOCK" AS is_publication_blocked_by_atlas,
        atlas.is_same_property_owner,
        FIRST_VALUE(clp.id_house_listing) OVER(
            PARTITION BY clp.id_house 
            ORDER BY IF(clp.is_last_contract_signed_by_house, 1, 0) DESC, IF(clp.is_last_house_listing, 1, 0) DESC
        ) = clp.id_house_listing AS is_last_available_comparison,
        FIRST_VALUE(clp.id_house_listing) OVER(
            PARTITION BY clp.id_house 
            ORDER BY IF(clp.dt_paid IS NOT NULL, 1, 0) DESC, clp.ts_contract_signed DESC
        ) = clp.id_house_listing AS is_last_listing_purchase,
        clp.dt_paid,
        clp.dt_contract_termination,
        clp.ts_contract_signed,
        clp.ts_house_inactived,
        clp.ts_house_registration
    FROM
        datalake_ciq.ciq_listing_purchase AS clp
    LEFT JOIN
        atlas_house_deduplication AS atlas
            ON atlas.id_house = clp.id_house
)
SELECT DISTINCT
    XXHASH64(
        clp.id_listing_purchase,
        parsed.id_house,
        parsed.id_ciq_user,
        parsed.consultant_type,
        parsed.business_context
    ) AS id_listing_duplicity,
    clp.id_listing_purchase,
    clp.id_house,
    clp.id_ciq_user,
    clp.id_owner,
    clp.id_contract,
    clp.id_atlas_duplicity,
    clp.id_address_parsed_duplicity,
    parsed.id_listing_purchase AS id_similar_listing_purchase,
    parsed.id_house AS id_similar_house,
    parsed.id_ciq_user AS id_similar_house_ciq_user,
    parsed.id_owner AS id_similar_house_owner,
    parsed.id_contract AS id_similar_contract,
    parsed.listing_status AS similar_house_listing_status,
    clp.atlas_duplicity_action,
    clp.atlas_duplicity_reason,
    parsed.consultant_type AS similar_house_consultant_type,
    parsed.business_context AS similar_house_business_context,
    parsed.total_days_since_house_inactived,
    parsed.is_house_inactive AS is_similiar_house_inactive,  
    parsed.dt_paid IS NOT NULL AS is_similiar_house_paid,
    COALESCE(parsed.id_ciq_user = clp.id_ciq_user, FALSE) AS is_same_ciq,
    COALESCE(parsed.id_owner = clp.id_owner, clp.is_same_property_owner, FALSE) AS is_same_owner,
    parsed.id_house IS NOT NULL AS is_address_parsed_duplicity,
    clp.is_atlas_atlas_duplicity,
    clp.is_publication_blocked_by_atlas,
    parsed.has_republication AS has_similiar_house_republication,
    parsed.dt_paid AS dt_similiar_house_paid,
    parsed.dt_contract_termination AS dt_similiar_house_contract_termination,
    parsed.ts_contract_signed AS ts_similiar_house_contract_signed,
    parsed.ts_house_inactived AS ts_similiar_house_inactived,
    clp.ts_house_registration,
    parsed.ts_house_registration AS ts_similiar_house_registration,
    NOW() AS ts_load
FROM
    ciq_listing_purchase AS clp
LEFT JOIN
    ciq_listing_purchase AS parsed
        ON parsed.id_address_parsed_duplicity = clp.id_address_parsed_duplicity
        AND parsed.parsed_first_listing_order < clp.parsed_first_listing_order
        AND parsed.is_last_listing_purchase IS TRUE
WHERE
    clp.is_last_available_comparison IS TRUE
    AND clp.consultant_type = 'CIQ_FULL'
    AND clp.business_context = 'RENT'
    AND (
        parsed.id_house IS NOT NULL
        OR clp.id_atlas_duplicity IS NOT NULL
    )