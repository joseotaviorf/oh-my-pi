WITH first_listing_conditions AS (
    SELECT 
        t.id_house,
        t.id_ciq_user_rent,
        t.id_ciq_user_sale,
        t.id_similar_previous_house,
        t.id_similar_first_house,
        t.house_listing_status,
        t.supply_source,
        t.days_between_fl_hybrid,
        t.hybrid_creation_order,
        t.supply_source_rent,
        t.supply_source_sale,
        t.consultant_type_rent,
        t.consultant_type_sale,

        --- GENERAL RULE FOR SALE
        CASE
            WHEN t.days_between_fl_to_ccv <= 60 
                OR t.dt_min_published_accumulated_days_sale IS NOT NULL 
                THEN TRUE
            ELSE FALSE
        END AS is_valid_compliance_general_rule_sale,
        --- GENERAL RULE FOR RENT
        CASE
            WHEN t.days_between_fl_to_cs <= 60 
                OR t.dt_min_published_accumulated_days_rent IS NOT NULL 
                THEN TRUE
            ELSE FALSE
        END AS is_valid_compliance_general_rule_rent,

        --- DUPLICATE - previous house
        CASE
            WHEN t.id_similar_previous_house IS NULL THEN NULL
            WHEN previous_house.house_listing_status = 'SOLD' THEN TRUE
            WHEN previous_house.house_listing_status IN ('RENTED', 'PUBLISHED') THEN FALSE
            WHEN COALESCE(t.id_ciq_user_rent, t.id_ciq_user_sale) = COALESCE(previous_house.id_ciq_user_rent, previous_house.id_ciq_user_sale) THEN FALSE
            WHEN DATE_DIFF(t.ts_first_listing, previous_house.ts_last_depublication) <= 7 AND previous_house.supply_source = '3P' THEN FALSE
            WHEN DATE_DIFF(t.ts_first_listing, previous_house.ts_last_depublication) <= 60 AND previous_house.supply_source <> '3P' THEN FALSE
            ELSE TRUE
        END AS is_valid_duplicated_previous_house,

        --- DUPLICATE - first house
        CASE
            WHEN t.id_similar_first_house IS NULL THEN NULL
            WHEN first_house.house_listing_status = 'SOLD' THEN TRUE
            WHEN first_house.house_listing_status IN ('RENTED', 'PUBLISHED') THEN FALSE
            WHEN COALESCE(t.id_ciq_user_rent, t.id_ciq_user_sale) = COALESCE(first_house.id_ciq_user_rent, first_house.id_ciq_user_sale) THEN FALSE
            WHEN DATE_DIFF(t.ts_first_listing, first_house.ts_last_depublication) <= 7 AND first_house.supply_source = '3P' THEN FALSE
            WHEN DATE_DIFF(t.ts_first_listing, first_house.ts_last_depublication) <= 60 AND first_house.supply_source <> '3P' THEN FALSE
            ELSE TRUE
        END AS is_valid_duplicated_first_house,

        --- HYBRID RULE + SUPPLY SOURCE RULE FOR RENT
        CASE
            WHEN t.is_hybrid_house IS FALSE THEN NULL
            WHEN t.hybrid_creation_order = 'RENT > SALE' THEN TRUE
            WHEN t.hybrid_creation_order = 'CREATED AS A HYBRID' AND t.is_hybrid_house IS TRUE THEN TRUE
            WHEN t.hybrid_creation_order = 'SALE > RENT'
                AND t.is_hybrid_house IS TRUE 
                AND t.days_between_fl_hybrid <= 60 
                THEN TRUE
            ELSE FALSE
        END AS is_valid_hybrid_rent,
        --- HYBRID RULE + SUPPLY SOURCE RULE FOR SALE
        CASE
            WHEN t.is_hybrid_house IS FALSE THEN NULL
            WHEN t.hybrid_creation_order = 'SALE > RENT' THEN TRUE
            WHEN t.hybrid_creation_order = 'CREATED AS A HYBRID' AND t.is_hybrid_house IS TRUE THEN TRUE
            WHEN t.hybrid_creation_order = 'RENT > SALE'
                AND t.is_hybrid_house IS TRUE 
                AND t.days_between_fl_hybrid <= 60 
                THEN TRUE
            ELSE FALSE
        END AS is_valid_hybrid_sale,
        --- INDICA AI RULE
        t.is_indica_ai IS TRUE AS is_invalid_by_indica_ai,

        --- INVALIDATION REASON GENERAL RULE
        IF(
            is_valid_compliance_general_rule_sale IS FALSE,
            "[General rule] The listing does not comply with the general rule: it must remain published for at least 2 days or have a signed contract within 60 days of the first publication.",
            NULL
        ) AS reason_invalidation_general_rule_sale,
        IF(
            is_valid_compliance_general_rule_rent IS FALSE,
            "[General rule] The listing does not comply with the general rule: it must remain published for at least 2 days or have a signed contract within 60 days of the first publication.",
            NULL
        ) AS reason_invalidation_general_rule_rent,

        --- INVALIDATION REASON DUPLICATED - previous house
        CASE
            WHEN is_valid_duplicated_previous_house IS NOT FALSE THEN NULL
            WHEN previous_house.house_listing_status IN ('RENTED', 'PUBLISHED') THEN "[Duplicate listing] A previous house listing is still active or rented."
            WHEN COALESCE(t.id_ciq_user_rent, t.id_ciq_user_sale) = COALESCE(previous_house.id_ciq_user_rent, previous_house.id_ciq_user_sale) 
                THEN "[Duplicate listing] The previous listing was not sold and was published by the same CIQ user."
            WHEN DATE_DIFF(t.ts_first_listing, previous_house.ts_last_depublication) <= 7 AND previous_house.supply_source = '3P'
                THEN "[Duplicate listing] The last depublication for a 3P listing occurred less than 7 days ago."
            WHEN DATE_DIFF(t.ts_first_listing, previous_house.ts_last_depublication) <= 60 AND previous_house.supply_source <> '3P'
                THEN "[Duplicate listing] The last depublication for a CIQ listing occurred less than 60 days ago."
        END AS reason_invalidation_duplicated_previous_house,

        --- INVALIDATION REASON DUPLICATED - first house
        CASE
            WHEN is_valid_duplicated_first_house IS NOT FALSE THEN NULL
            WHEN first_house.house_listing_status IN ('RENTED', 'PUBLISHED') THEN "[Duplicate listing] A first house listing is still active or rented."
            WHEN COALESCE(t.id_ciq_user_rent, t.id_ciq_user_sale) = COALESCE(first_house.id_ciq_user_rent, first_house.id_ciq_user_sale) 
                THEN "[Duplicate listing] The first listing was not sold and was published by the same CIQ user."
            WHEN DATE_DIFF(t.ts_first_listing, first_house.ts_last_depublication) <= 7 AND first_house.supply_source = '3P'
                THEN "[Duplicate listing] The last depublication for a 3P listing occurred less than 7 days ago."
            WHEN DATE_DIFF(t.ts_first_listing, first_house.ts_last_depublication) <= 60 AND first_house.supply_source <> '3P'
                THEN "[Duplicate listing] The last depublication for a CIQ listing occurred less than 60 days ago."
        END AS reason_invalidation_duplicated_first_house,

        --- INVALIDATION REASON HYBRID RULE (RENT)
        CASE
            WHEN is_valid_hybrid_rent IS TRUE OR is_valid_hybrid_rent IS NULL THEN NULL
            WHEN t.days_between_fl_hybrid > 60 
                    THEN "[Migrated hybrid] The migration occurred more than 60 days after the first publication."
            WHEN COALESCE(t.is_signed_cs_within_60_days, FALSE) IS FALSE 
                THEN "[Migrated hybrid] No contract was signed within 60 days after the migration."
        END AS reason_invalidation_hybrid_rent,

        --- INVALIDATION REASON HYBRID RULE (SALE)
        CASE
            WHEN is_valid_hybrid_sale IS TRUE OR is_valid_hybrid_sale IS NULL THEN NULL
            WHEN t.days_between_fl_hybrid > 60
                THEN "[Migrated hybrid] The migration occurred more than 60 days after the first publication."
            WHEN COALESCE(t.is_signed_ccv_within_60_days, FALSE) IS FALSE
                THEN "[Migrated hybrid] No contract was signed within 60 days after the migration."
        END AS reason_invalidation_hybrid_sale,

        --- INVALIDATION REASON INDICA AI
        IF(
            t.is_indica_ai IS TRUE,
            "[Supply source] The first publication was created through Indica Ai as a supply source.",
            NULL
        ) AS reason_invalidation_indica_ai,

        t.is_hybrid_house,
        t.is_signed_ccv_within_60_days,
        t.is_signed_cs_within_60_days,
        --- DATES FROM COMPLIANCE GENERAL RULE FOR SALE AND RENT
        LEAST(t.dt_min_published_accumulated_days_sale, t.ts_first_contract_signed_sale) AS dt_compliance_general_rule_sale,
        LEAST(t.dt_min_published_accumulated_days_rent, t.ts_first_contract_signed_rent) AS dt_compliance_general_rule_rent,
        t.dt_min_published_accumulated_days_sale,
        t.dt_min_published_accumulated_days_rent,
        t.ts_first_contract_signed_sale,
        t.ts_first_contract_signed_rent,
        t.ts_first_listing_sale,
        t.ts_initial_first_listing_sale,
        t.ts_first_listing_rent,
        t.ts_last_depublication
    FROM 
        datalake_listing_deduplication.valid_first_listing AS t
    LEFT JOIN
        datalake_listing_deduplication.valid_first_listing AS previous_house
            ON previous_house.id_house = t.id_similar_previous_house
    LEFT JOIN
        datalake_listing_deduplication.valid_first_listing AS first_house
            ON first_house.id_house = t.id_similar_first_house
    WHERE
        COALESCE(t.id_ciq_user_rent, t.id_ciq_user_sale) IS NOT NULL
        AND (
            t.consultant_type_rent IN ('CIQ_FULL', 'CIQ_MANAGER')
            OR t.consultant_type_sale IN ('CIQ_FULL', 'CIQ_MANAGER')
        )
),
union_first_listing AS (
    SELECT
        t.id_house,
        t.id_similar_previous_house,
        t.id_similar_first_house,
        CAST(t.id_ciq_user_rent AS BIGINT) AS id_user,
        "RENT" AS business_context,
        t.consultant_type_rent AS consultant_type,
        t.house_listing_status,
        t.supply_source,
        t.supply_source_rent AS supply_source_by_context,
        t.days_between_fl_hybrid,
        t.hybrid_creation_order,
        t.reason_invalidation_duplicated_previous_house,
        t.reason_invalidation_duplicated_first_house,
        t.reason_invalidation_hybrid_rent AS reason_invalidation_hybrid,
        t.reason_invalidation_indica_ai,
        t.reason_invalidation_general_rule_rent AS reason_invalidation_general_rule,
        t.is_valid_duplicated_previous_house,
        t.is_valid_duplicated_first_house,
        t.is_valid_hybrid_rent AS is_valid_hybrid,
        t.is_invalid_by_indica_ai,
        t.is_valid_compliance_general_rule_rent AS is_valid_compliance_general_rule,
        t.is_hybrid_house,
        t.is_signed_cs_within_60_days AS is_signed_contract_within_60_days,
        t.dt_compliance_general_rule_rent AS dt_compliance_general_rule,
        t.dt_min_published_accumulated_days_rent AS dt_min_published_accumulated_days,
        t.ts_first_contract_signed_rent AS ts_first_contract_signed,
        t.ts_first_listing_rent AS ts_original_first_listing,
        t.ts_first_listing_rent AS ts_final_first_listing,
        t.ts_last_depublication
    FROM
        first_listing_conditions t
    WHERE
        t.ts_first_listing_rent IS NOT NULL
        AND t.id_ciq_user_rent IS NOT NULL
    UNION ALL
    SELECT
        t.id_house,
        t.id_similar_previous_house,
        t.id_similar_first_house,
        CAST(t.id_ciq_user_sale AS BIGINT) AS id_user,
        "SALE" AS business_context,
        t.consultant_type_sale AS consultant_type,
        t.house_listing_status,
        t.supply_source,
        t.supply_source_sale AS supply_source_by_context,
        t.days_between_fl_hybrid,
        t.hybrid_creation_order,
        t.reason_invalidation_duplicated_previous_house,
        t.reason_invalidation_duplicated_first_house,
        t.reason_invalidation_hybrid_sale AS reason_invalidation_hybrid,
        t.reason_invalidation_indica_ai,
        t.reason_invalidation_general_rule_sale AS reason_invalidation_general_rule,
        t.is_valid_duplicated_previous_house,
        t.is_valid_duplicated_first_house,
        t.is_valid_hybrid_sale AS is_valid_hybrid,
        t.is_invalid_by_indica_ai,
        t.is_valid_compliance_general_rule_sale AS is_valid_compliance_general_rule,
        t.is_hybrid_house,
        t.is_signed_ccv_within_60_days AS is_signed_contract_within_60_days,
        t.dt_compliance_general_rule_sale AS dt_compliance_general_rule,
        t.dt_min_published_accumulated_days_sale AS dt_min_published_accumulated_days,
        t.ts_first_contract_signed_sale AS ts_first_contract_signed,
        t.ts_first_listing_sale AS ts_original_first_listing,
        t.ts_initial_first_listing_sale AS ts_final_first_listing,
        t.ts_last_depublication
    FROM
        first_listing_conditions t
    WHERE
        t.ts_first_listing_sale IS NOT NULL
        AND t.id_ciq_user_sale IS NOT NULL
)
SELECT
    ufl.id_house,
    ufl.id_similar_previous_house,
    ufl.id_similar_first_house,
    ufl.id_user,
    ciq.uuid_person,
    ciq.id_partner,
    cag.id_agent,
    ufl.business_context,
    ufl.consultant_type,
    ufl.house_listing_status,
    ufl.supply_source,
    ufl.supply_source_by_context,
    ufl.days_between_fl_hybrid,
    ufl.hybrid_creation_order,
    IF(
        (
            ufl.is_valid_duplicated_previous_house IS FALSE
            OR ufl.is_valid_duplicated_first_house IS FALSE
            OR ufl.is_valid_hybrid IS FALSE
            OR ufl.is_invalid_by_indica_ai IS TRUE 
            OR ufl.is_valid_compliance_general_rule IS FALSE
        ),
        FILTER(
            ARRAY(
                ufl.reason_invalidation_duplicated_previous_house,
                ufl.reason_invalidation_duplicated_first_house,
                ufl.reason_invalidation_hybrid,
                ufl.reason_invalidation_indica_ai,
                ufl.reason_invalidation_general_rule
            ),
            x -> x IS NOT NULL
        ),
        NULL
    ) AS invalidation_reasons,
    IF(
        (
            ufl.is_valid_duplicated_previous_house IS FALSE
            OR ufl.is_valid_duplicated_first_house IS FALSE
            OR ufl.is_valid_hybrid IS FALSE
            OR ufl.is_invalid_by_indica_ai IS TRUE 
            OR ufl.is_valid_compliance_general_rule IS FALSE
        ),
        FALSE,
        TRUE
    ) AS is_first_listing_valid,
    ufl.is_valid_duplicated_previous_house,
    ufl.is_valid_duplicated_first_house,
    ufl.is_valid_hybrid,
    ufl.is_invalid_by_indica_ai,
    ufl.is_valid_compliance_general_rule,
    ufl.is_hybrid_house,
    ufl.is_signed_contract_within_60_days,
    ufl.dt_compliance_general_rule,
    ufl.dt_min_published_accumulated_days,
    ufl.ts_first_contract_signed,
    ufl.ts_original_first_listing,
    ufl.ts_final_first_listing,
    ufl.ts_last_depublication
FROM
    union_first_listing AS ufl
LEFT JOIN
    datalake_ebdb_agents.ciq_users AS ciq
        ON ciq.id_user = ufl.id_user
        AND ciq.is_last_status
LEFT JOIN
    datalake_ebdb_agents.ciq_agents AS cag
        ON cag.id_user = ufl.id_user
        AND cag.id_partner = ciq.id_partner