SELECT DISTINCT
    l.id,
    rg.id_country,
    l.id_agent,
    l.id_region,
    l.id_external,
    l.id_lead_owner,
    user_affiliate.id AS id_user_has_indicated,
    l.id_affiliate_has_indicated,
    rg.country_code,
    l.address,
    l.house_number,
    l.complement,
    l.neighborhood,
    l.zip_code,
    l.city,
    l.total_area,
    l.advertiser_name,
    l.bathrooms,
    l.bedrooms,
    l.suites,
    l.ad_url,
    l.advertiser_phone,
    l.type,
    l.email,
    l.pick_up_email,
    l.pick_up_phone,
    l.lat,
    l.lng,
    l.condo_price,
    l.iptu,
    l.status,
    l.source,
    l.unbounce_page_variant,
    l.unbounce_page_name,
    l.reason AS original_reason,
    COALESCE(lead_reason.reason, l.reason) AS reason,
    -- Consider Old and New reasons
    lead_reason.reason_detail,
    ol.name AS lead_owner_name,
    ol.email AS lead_owner_email,
    l.affiliate_type,
    ad.operation_city AS affiliate_operation_city,
    l.utm_medium,
    l.utm_campaign,
    l.utm_source,
    l.real_estate_agency_code,
    l.sale_price,
    CASE
        WHEN lead_reason.reason_detail IN ('CONTACT_ON_BLOCK_LIST', 'CONTACT_KNOW_OWNER','CONTACT_WASNT_THE_HOUSE_OWNER','CONTACT_DIDNT_EXIST','OWNER_DIDNT_ANSWER_PHONE',
                                    'HOUSE_ONLY_FOR_SELLING','HOUSE_WITH_BAD_CONDITIONS','HOUSE_WAS_A_BUSINESS_REAL_ESTATE','HOUSE_PRICE_WAS_OUT_OF_BOUNDS',
                                    'HOUSE_WAS_OUT_OF_HOUSE_RENTING_REGIONS','HOUSE_WAS_OUT_OF_HOUSE_SALES_REGIONS','HOUSE_ALREADY_SOLD','HOUSE_ALREADY_PUBLISHED',
                                    'DUPLICATED_LEAD')
            THEN 'Nunca'
        WHEN lead_reason.reason_detail IN ('ISSUES_WITH_HOUSE_ENTRANCE_CONDITIONS','HOUSE_UNDER_EXCLUSIVITY_CONTRACT','OWNER_WITH_PRIME_PROFILE',
                                    'OWNER_DIDNT_WANT_ADMINISTRATION','OWNER_CONSIDERED_ADMINISTRATION_FEE_TOO_HIGH','OWNER_CONSIDERED_BROKERAGE_FEE_TOO_HIGH',
                                    'OWNER_CONSIDERED_SALE_FEE_TOO_HIGH','OWNER_DIDNT_SELECT_CONTEXT')
            THEN 'Curto Prazo'
        WHEN lead_reason.reason_detail IN ('SEASONAL_RENT','ONLY_PART_OF_THE_HOUSE_WAS_AVAILABLE_FOR_RENTING','ISSUES_WITH_HOUSE_DOCUMENTATION','HOUSE_UNDER_MAJOR_RENOVATION',
                                    'HOUSE_ALREADY_RENTED','OWNER_GAVE_UP_RENTING','OWNER_DISAGREE_CHARGES_PAYMENTS','OWNER_DIDNT_LISTEN_TO_PITCH',
                                    'OWNER_DISAGREE_PAYMENT_TIMING','OWNER_GAVE_UP_SELLING','PROPERTY_IN_OFFPLANT','PROPERTY_IN_JUDICIAL_INVENTORY')
            THEN 'Longo Prazo'
    END AS deadline_of_new_contact,
    COALESCE(l.extra_infos LIKE '%source=b2b_%', FALSE) AS is_b2b,
    l.is_inside_operation_area,
    l.is_enriched_data,
    l.is_to_be_mentioned,
    COALESCE(l.is_for_rent, TRUE) AS is_for_rent,
    l.is_for_sale,
    l.has_processed,
    l.has_automatically_discarded,
    l.dt_picked_up,
    l.dt_ad_created,
    ad.ts_operation_start AS ts_affiliate_operation_start,
    l.ts_created,
    l.ts_updated
FROM
    datalake_ebdb_clean.lead AS l
LEFT JOIN
    datalake_ebdb_clean.ownerlead AS ol
        ON ol.id = l.id_lead_owner
LEFT JOIN
    datalake_ebdb_clean.affiliate_data AS ad
        ON ad.id = l.id_affiliate_has_indicated
LEFT JOIN
    datalake_ebdb_clean.user AS user_affiliate
        ON ad.id = user_affiliate.id_affiliates
LEFT JOIN
    datalake_ebdb_clean.lead_reason AS lead_reason
 	    ON l.reason = lead_reason.reason_detail
LEFT JOIN
    datalake_region.region AS rg
        ON l.id_region = rg.id