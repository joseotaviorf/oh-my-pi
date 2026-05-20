WITH atlas_similar_house_info AS (
    SELECT
        ahd.id_duplicity AS id_atlas_duplicity,
        clp.id_house,
        ahd.id_similar_house,
        clp.id_ciq_user,
        clp.id_contract,
        ahd.id_owner,
        clp.id_accounting_entry,
        ahd.duplicity_reason,
        clp.total_days_since_house_inactived,
        ahd.is_same_property_owner,
        ahd.action_type = 'BLOCK' AS is_blocked_by_atlas,
        ahd.ts_property_updated,
        clp.is_house_inactive,
        clp.ts_house_registration,
        clp.dt_paid,
        clp.dt_contract_termination,
        clp.ts_house_inactived,
        ahd.ts_property_updated AS ts_property_dedup_updated
    FROM
        datalake_listing_deduplication.atlas_house_deduplication AS ahd
    JOIN
        datalake_ciq.ciq_listing_purchase AS clp
            ON ahd.id_similar_house = clp.id_house
    WHERE
        clp.id_contract IS NOT NULL
        AND clp.dt_paid IS NOT NULL
),
list_exclusion AS (
    SELECT
        clp.id_house,
        clp.id_ciq_user,
        clp.id_owner,
        ad.id_similar_house AS id_similar_paid_house,
        ad.id_ciq_user AS id_paid_ciq_user,
        ad.id_owner AS id_paid_owner,
        ad.id_contract AS id_paid_contract,
        ad.id_accounting_entry,
        ad.id_atlas_duplicity,
        NULL AS id_address_parsed_duplicity,
        clp.address,
        "ATLAS_DEDUP" AS duplicity_method_applied,
        ad.total_days_since_house_inactived,
        ad.is_house_inactive AS is_paid_house_inactive,  
        COALESCE(ad.id_ciq_user = clp.id_ciq_user, FALSE) AS is_same_ciq,
        ad.is_same_property_owner AS is_same_owner,
        NULL AS is_address_parsed_similar_house,
        TRUE AS is_atlas_similar_house,
        ad.is_blocked_by_atlas,
        ad.dt_paid,
        ad.dt_contract_termination AS dt_paid_contract_termination,
        ad.ts_house_inactived AS ts_paid_house_inactived,
        clp.ts_house_registration,
        ad.ts_house_registration AS ts_paid_house_registration
    FROM
        datalake_ciq.ciq_listing_purchase AS clp
    JOIN
        atlas_similar_house_info AS ad
            ON ad.id_house = clp.id_house
    UNION ALL
    SELECT
        clp.id_house,
        clp.id_ciq_user,
        clp.id_owner,
        parsed.id_house AS id_similar_paid_house,
        parsed.id_ciq_user AS id_paid_ciq_user,
        parsed.id_owner AS id_paid_owner,
        parsed.id_contract AS id_paid_contract,
        parsed.id_accounting_entry,
        NULL AS id_atlas_duplicity,
        parsed.id_address_parsed_duplicity,
        clp.address,
        "ADDRESS_PARSED" AS duplicity_method_applied,
        parsed.total_days_since_house_inactived,
        parsed.is_house_inactive AS is_paid_house_inactive,  
        COALESCE(parsed.id_ciq_user = clp.id_ciq_user, FALSE) AS is_same_ciq,
        COALESCE(parsed.id_owner = clp.id_owner, FALSE) AS is_same_owner,
        FALSE AS is_address_parsed_similar_house,
        NULL AS is_atlas_similar_house,
        NULL AS is_blocked_by_atlas,
        parsed.dt_paid,
        parsed.dt_contract_termination AS dt_paid_contract_termination,
        parsed.ts_house_inactived AS ts_paid_house_inactived,
        clp.ts_house_registration,
        parsed.ts_house_registration AS ts_paid_house_registration
    FROM
        datalake_ciq.ciq_listing_purchase AS clp
    JOIN
        datalake_ciq.ciq_listing_purchase AS parsed
            ON parsed.id_address_parsed_duplicity = clp.id_address_parsed_duplicity
            AND parsed.parsed_first_listing_order < clp.parsed_first_listing_order
    WHERE
        parsed.id_contract IS NOT NULL
        AND parsed.dt_paid IS NOT NULL
)
SELECT
    n.id_house,
    n.id_ciq_user,
    n.id_owner,
    n.id_similar_paid_house,
    n.id_paid_ciq_user,
    n.id_paid_owner,
    n.id_paid_contract,
    n.id_accounting_entry,
    COALESCE(n.id_atlas_duplicity, n2.id_atlas_duplicity) AS id_atlas_duplicity,
    COALESCE(n.id_address_parsed_duplicity, n2.id_address_parsed_duplicity) AS id_address_parsed_duplicity,
    n.address,
    ARRAY_COMPACT(ARRAY(n.duplicity_method_applied, n2.duplicity_method_applied)) AS duplicity_method_applied,
    n.total_days_since_house_inactived,
    TIMESTAMPDIFF(DAY, n.ts_paid_house_inactived, n.dt_paid_contract_termination) AS total_days_inactive_since_contract_termination,
    TIMESTAMPDIFF(DAY, n.ts_paid_house_inactived, n.dt_paid) AS total_days_inactive_since_paid,
    n.is_paid_house_inactive,  
    n.is_same_ciq,
    n.is_same_owner,
    COALESCE(n.is_address_parsed_similar_house, n2.is_address_parsed_similar_house, FALSE) AS is_address_parsed_similar_house,
    COALESCE(n.is_atlas_similar_house, n2.is_atlas_similar_house, FALSE) AS is_atlas_similar_house,
    COALESCE(n.is_blocked_by_atlas, n2.is_blocked_by_atlas, FALSE) AS is_blocked_by_atlas,
    n.dt_paid,
    n.dt_paid_contract_termination,
    n.ts_paid_house_inactived,
    n.ts_house_registration,
    n.ts_paid_house_registration
FROM 
    list_exclusion AS n
LEFT JOIN
    list_exclusion AS n2
        ON n.id_house = n2.id_house
        AND n.id_similar_paid_house = n2.id_similar_paid_house
        AND n.duplicity_method_applied <> n2.duplicity_method_applied
GROUP BY ALL