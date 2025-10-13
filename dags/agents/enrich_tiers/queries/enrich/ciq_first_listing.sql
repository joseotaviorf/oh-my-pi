WITH first_listing_conditions AS (
    SELECT 
        t.id_house,
        t.id_house_duplicated AS id_previous_duplicated_house,
        t.id_user_listing_registrant_rent AS id_ciq_user_rent,
        t.id_user_listing_registrant_sale AS id_ciq_user_sale,
        t2.id_user_listing_registrant_rent AS id_ciq_user_rent_duplicated_house,
        t2.id_user_listing_registrant_sale AS id_ciq_user_sale_duplicated_house,
        t.uuid_person_sale,
        t.uuid_person_rent,
        t.id_partner_sale,
        t.id_partner_rent,
        t.id_agent_sale,
        t.id_agent_rent,
        t.house_listing_status,
        t2.house_listing_status AS house_listing_status_duplicated_house,
        t.supply_source,
        t2.supply_source AS supply_source_duplicated_house,
        t.days_between_fl_hybrid,
        t.hybrid_creation_order,
        t.supply_source_rent,
        t.supply_source_sale,
        t.consultant_type_rent,
        t.consultant_type_sale,

        --- GENERAL RULE FOR SALE
        CASE
            WHEN t.days_between_fl_to_ccv <= 15 
                OR t.dt_15_published_accumulated_days_sale IS NOT NULL 
                THEN TRUE
            ELSE FALSE
        END AS is_compliance_general_rule_sale,
        --- GENERAL RULE FOR RENT
        CASE
            WHEN t.days_between_fl_to_cs <= 15 
                OR t.dt_15_published_accumulated_days_rent IS NOT NULL 
                OR t.is_draft_contract IS TRUE
                THEN TRUE
            ELSE FALSE
        END AS is_compliance_general_rule_rent,
        --- DUPLICATE
        CASE
            WHEN t.id_house_duplicated IS NULL THEN NULL
            WHEN t2.house_listing_status = 'SOLD' THEN TRUE
            WHEN t2.house_listing_status <> 'SOLD'
                AND (
                    t.id_user_listing_registrant_rent IN (t2.id_user_listing_registrant_rent, t2.id_user_listing_registrant_sale)
                    OR t.id_user_listing_registrant_sale IN (t2.id_user_listing_registrant_rent, t2.id_user_listing_registrant_sale)
                )
                THEN FALSE
            WHEN t2.house_listing_status IN ('RENTED', 'PUBLISHED') THEN FALSE
            WHEN DATE_DIFF(t.ts_first_listing, t2.ts_last_depublication) <= 7 AND t2.supply_source = '3P' THEN FALSE
            WHEN DATE_DIFF(t.ts_first_listing, t2.ts_last_depublication) <= 180 AND t2.supply_source <> '3P' THEN FALSE
            ELSE TRUE
        END AS is_valid_duplicated,
        --- HYBRID RULE + SUPPLY SOURCE RULE FOR RENT
        CASE
            WHEN t.hybrid_creation_order = 'RENT > SALE' THEN TRUE
            WHEN t.is_hybrid_house IS FALSE THEN NULL
            WHEN t.hybrid_creation_order = 'CREATED AS A HYBRID' AND t.is_hybrid_house IS TRUE THEN TRUE
            WHEN t.hybrid_creation_order = 'SALE > RENT'
                AND t.is_hybrid_house IS TRUE 
                AND t.days_between_fl_hybrid <= 60 
                AND t.is_signed_cs_within_60_days IS TRUE
                AND (t.supply_source = 'CIQ' AND t.supply_source_rent <> '3P')
                THEN TRUE
            ELSE FALSE
        END AS is_valid_hybrid_rent,
        --- HYBRID RULE + SUPPLY SOURCE RULE FOR SALE
        CASE
            WHEN t.hybrid_creation_order = 'SALE > RENT' THEN TRUE
            WHEN t.is_hybrid_house IS FALSE THEN NULL
            WHEN t.hybrid_creation_order = 'CREATED AS A HYBRID' AND t.is_hybrid_house IS TRUE THEN TRUE
            WHEN t.hybrid_creation_order = 'RENT > SALE'
                AND t.is_hybrid_house IS TRUE 
                AND t.days_between_fl_hybrid <= 60 
                AND t.is_signed_ccv_within_60_days IS TRUE
                AND (t.supply_source = 'CIQ' AND t.supply_source_sale <> '3P')
                THEN TRUE
            ELSE FALSE
        END AS is_valid_hybrid_sale,
        --- INDICA AI RULE
        t.is_indica_ai IS TRUE AS is_invalid_by_indica_ai,


        --- INVALIDATION REASON GENERAL RULE
        IF(
            is_compliance_general_rule_sale IS FALSE,
            "[General rule] The listing does not comply with the general rule: it must remain published for at least 15 days or have a signed contract within that period.",
            NULL
        ) AS reason_invalidation_general_rule_sale,
        IF(
            is_compliance_general_rule_rent IS FALSE,
            "[General rule] The listing does not comply with the general rule: it must remain published for at least 15 days or have a signed or draft contract within that period.",
            NULL
        ) AS reason_invalidation_general_rule_rent,

        --- INVALIDATION REASON DUPLICATED
        CASE
            WHEN t2.house_listing_status <> 'SOLD'
                AND (
                    t.id_user_listing_registrant_rent IN (t2.id_user_listing_registrant_rent, t2.id_user_listing_registrant_sale)
                    OR t.id_user_listing_registrant_sale IN (t2.id_user_listing_registrant_rent, t2.id_user_listing_registrant_sale)
                )
                THEN "[Duplicate listing] The previous listing was not sold and was published by the same CIQ user."
            WHEN t2.house_listing_status IN ('RENTED', 'PUBLISHED')
                THEN "[Duplicate listing] A previous house listing is still active or rented."
            WHEN DATE_DIFF(t.ts_first_listing, t2.ts_last_depublication) <= 7 AND t2.supply_source = '3P'
                THEN "[Duplicate listing] The last depublication for a 3P listing occurred less than 7 days ago."
            WHEN DATE_DIFF(t.ts_first_listing, t2.ts_last_depublication) <= 180 AND t2.supply_source <> '3P'
                THEN "[Duplicate listing] The last depublication for a CIQ listing occurred less than 180 days ago."
        END AS reason_invalidation_duplicated,

        --- INVALIDATION REASON HYBRID RULE (RENT)
        CASE
            WHEN is_valid_hybrid_rent IS TRUE OR is_valid_hybrid_rent IS NULL THEN NULL
            WHEN t.days_between_fl_hybrid > 60 
                    THEN "[Migrated hybrid] The migration occurred more than 60 days after the first publication."
            WHEN COALESCE(t.is_signed_cs_within_60_days, FALSE) IS FALSE 
                THEN "[Migrated hybrid] No contract was signed within 60 days after the migration."
            WHEN NOT (t.supply_source = 'CIQ' AND t.supply_source_rent <> '3P')
                THEN "[Migrated hybrid] The migration occurred from a 3P supply source."
            WHEN t.supply_source = 'CIQ' AND t.supply_source_rent IS NULL
                THEN "[Migrated Hybrid] The migration occurred, but we have no record of a supply source for the migrated context."
            WHEN t.supply_source IS NULL
                THEN "[Migrated Hybrid] The migration occurred, but we have no record of a supply source for the house."
        END AS reason_invalidation_hybrid_rent,

        --- INVALIDATION REASON HYBRID RULE (SALE)
        CASE
            WHEN is_valid_hybrid_sale IS TRUE OR is_valid_hybrid_sale IS NULL THEN NULL
            WHEN t.days_between_fl_hybrid > 60
                THEN "[Migrated hybrid] The migration occurred more than 60 days after the first publication."
            WHEN COALESCE(t.is_signed_ccv_within_60_days, FALSE) IS FALSE
                THEN "[Migrated hybrid] No contract was signed within 60 days after the migration."
            WHEN NOT (t.supply_source = 'CIQ' AND t.supply_source_sale <> '3P')
                THEN "[Migrated hybrid] The migration occurred from a 3P supply source."
            WHEN t.supply_source = 'CIQ' AND t.supply_source_sale IS NULL
                THEN "[Migrated Hybrid] The migration occurred, but we have no record of a supply source for the migrated context."
            WHEN t.supply_source IS NULL
                THEN "[Migrated Hybrid] The migration occurred, but we have no record of a supply source for the house."
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
        LEAST(t.dt_15_published_accumulated_days_sale, t.ts_first_contract_signed_sale) AS dt_compliance_general_rule_sale,
        LEAST(t.dt_15_published_accumulated_days_rent, t.ts_first_contract_signed_rent, t.ts_created_draft_contract_rent) AS dt_compliance_general_rule_rent,
        t.dt_15_published_accumulated_days_sale,
        t.dt_15_published_accumulated_days_rent,
        t.ts_first_contract_signed_sale,
        t.ts_first_contract_signed_rent,
        t.ts_created_draft_contract_rent,
        t.ts_first_listing_sale,
        t.ts_initial_first_listing_sale,
        t.ts_first_listing_rent,
        t.ts_last_depublication,
        t2.ts_last_depublication AS ts_last_depublication_duplicated_house
    FROM 
        datalake_listing_deduplication.valid_first_listing AS t
    LEFT JOIN
        datalake_listing_deduplication.valid_first_listing AS t2
            ON t2.id_house = t.id_house_duplicated
    WHERE
        t.consultant_type_rent IN ('CIQ_FULL', 'CIQ_MANAGER')
        AND COALESCE(t.id_user_listing_registrant_rent, t.id_user_listing_registrant_sale) IS NOT NULL
)
SELECT
    t.id_house,
    t.id_previous_duplicated_house,
    t.id_ciq_user_rent AS id_user,
    t.uuid_person_rent AS uuid_person,
    t.id_partner_rent AS id_partner,
    t.id_agent_rent AS id_agent,
    t.id_ciq_user_rent_duplicated_house,
    t.id_ciq_user_sale_duplicated_house,
    "RENT" AS business_context,
    t.consultant_type_rent AS consultant_type,
    t.house_listing_status,
    t.house_listing_status_duplicated_house,
    t.supply_source,
    t.supply_source_rent AS supply_source_by_context,
    t.supply_source_duplicated_house,
    t.days_between_fl_hybrid,
    t.hybrid_creation_order,
    IF(
        CASE
            WHEN t.is_valid_duplicated IS FALSE THEN FALSE
            WHEN t.is_valid_hybrid_rent IS FALSE THEN FALSE
            WHEN t.is_invalid_by_indica_ai IS TRUE THEN FALSE
            ELSE t.is_compliance_general_rule_rent
        END IS FALSE,
        FILTER(
            ARRAY(
                t.reason_invalidation_duplicated,
                t.reason_invalidation_hybrid_rent,
                t.reason_invalidation_indica_ai,
                t.reason_invalidation_general_rule_rent
            ),
            x -> x IS NOT NULL
        ),
        NULL
    ) AS invalidation_reasons,
    CASE
        WHEN t.is_valid_duplicated IS FALSE THEN FALSE
        WHEN t.is_valid_hybrid_rent IS FALSE THEN FALSE
        WHEN t.is_invalid_by_indica_ai IS TRUE THEN FALSE
        ELSE t.is_compliance_general_rule_rent
    END AS is_first_listing_valid,
    t.is_valid_duplicated,
    t.is_valid_hybrid_rent AS is_valid_hybrid,
    t.is_invalid_by_indica_ai,
    t.is_compliance_general_rule_rent AS is_compliance_general_rule,
    t.is_hybrid_house,
    t.is_signed_cs_within_60_days AS is_signed_contract_within_60_days,
    t.dt_compliance_general_rule_rent AS dt_compliance_general_rule,
    t.dt_15_published_accumulated_days_rent AS dt_15_published_accumulated_days,
    t.ts_first_contract_signed_rent AS ts_first_contract_signed,
    t.ts_created_draft_contract_rent AS ts_created_draft_contract,
    t.ts_first_listing_rent AS ts_original_first_listing,
    t.ts_first_listing_rent AS ts_final_first_listing,
    t.ts_last_depublication,
    t.ts_last_depublication_duplicated_house
FROM
    first_listing_conditions t
WHERE
    t.ts_first_listing_rent IS NOT NULL
    AND t.id_ciq_user_rent IS NOT NULL
UNION ALL
SELECT
    t.id_house,
    t.id_previous_duplicated_house,
    t.id_ciq_user_sale AS id_user,
    t.uuid_person_sale AS uuid_person,
    t.id_partner_sale AS id_partner,
    t.id_agent_sale AS id_agent,
    t.id_ciq_user_rent_duplicated_house,
    t.id_ciq_user_sale_duplicated_house,
    "SALE" AS business_context,
    t.consultant_type_sale AS consultant_type,
    t.house_listing_status,
    t.house_listing_status_duplicated_house,
    t.supply_source,
    t.supply_source_sale AS supply_source_by_context,
    t.supply_source_duplicated_house,
    t.days_between_fl_hybrid,
    t.hybrid_creation_order,
    IF(
        CASE
            WHEN t.is_valid_duplicated IS FALSE THEN FALSE
            WHEN t.is_valid_hybrid_sale IS FALSE THEN FALSE
            WHEN t.is_invalid_by_indica_ai IS TRUE THEN FALSE
            ELSE t.is_compliance_general_rule_sale
        END IS FALSE,
        FILTER(
            ARRAY(
                t.reason_invalidation_duplicated,
                t.reason_invalidation_hybrid_sale,
                t.reason_invalidation_indica_ai,
                t.reason_invalidation_general_rule_sale
            ),
            x -> x IS NOT NULL
        ),
        NULL
    ) AS invalidation_reasons,
    CASE
        WHEN t.is_valid_duplicated IS FALSE THEN FALSE
        WHEN t.is_valid_hybrid_sale IS FALSE THEN FALSE
        WHEN t.is_invalid_by_indica_ai IS TRUE THEN FALSE
        ELSE t.is_compliance_general_rule_sale
    END AS is_first_listing_valid,
    t.is_valid_duplicated,
    t.is_valid_hybrid_sale AS is_valid_hybrid,
    t.is_invalid_by_indica_ai,
    t.is_compliance_general_rule_sale AS is_compliance_general_rule,
    t.is_hybrid_house,
    t.is_signed_ccv_within_60_days AS is_signed_contract_within_60_days,
    t.dt_compliance_general_rule_sale AS dt_compliance_general_rule,
    t.dt_15_published_accumulated_days_sale AS dt_15_published_accumulated_days,
    t.ts_first_contract_signed_sale AS ts_first_contract_signed,
    NULL AS ts_created_draft_contract,
    t.ts_first_listing_sale AS ts_original_first_listing,
    t.ts_initial_first_listing_sale AS ts_final_first_listing,
    t.ts_last_depublication,
    t.ts_last_depublication_duplicated_house
FROM
    first_listing_conditions t
WHERE
    t.ts_first_listing_sale IS NOT NULL
    AND t.id_ciq_user_sale IS NOT NULL