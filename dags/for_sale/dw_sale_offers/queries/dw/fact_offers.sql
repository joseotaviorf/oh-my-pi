SELECT
    eso.id_offer AS sk_offer,
    eso.id_sale_flow AS sk_sale_flow,
    eso.id_house AS sk_house,
    eso.id_buyer AS sk_buyer,
    eso.id_owner AS sk_owner,
    COALESCE(eso.id_business_unit, -1) AS sk_business_unit,
    COALESCE(eso.sk_company_supply, -1) AS sk_company_supply,
    COALESCE(NULLIF(eso.sk_company_demand, -1), eso.id_company_demand, -1) AS sk_company_demand,
    COALESCE(eso.id_region,-1) AS sk_region,
    COALESCE(eso.id_booking,-1) AS sk_booking,
    COALESCE(eso.id_agent,-1) AS sk_agent,
    COALESCE(eso.id_user_agent, -1) AS sk_user_agent,
    COALESCE(eso.id_user_team_lead, -1) AS sk_user_team_lead,
    eso.id_user_consultant AS sk_user_consultant,
    eso.id_consultant AS sk_consultant,
    COALESCE(eso.id_closing_specialist, -1) AS sk_closing_specialist,
    COALESCE(sa_creator.sk_secretariat_user_version, -1) AS sk_secretariat_booking_creator,
    COALESCE(sa_offer_submitted_date.sk_secretariat_user_version, -1) AS sk_secretariat_on_offer_submitted,
    COALESCE(sa_offer_accepted_date.sk_secretariat_user_version, -1) AS sk_secretariat_on_offer_accepted,
    COALESCE(sa_offer_dismissed_date.sk_secretariat_user_version, -1) AS sk_secretariat_on_offer_dismissed,
    COALESCE(sa_sale_agreement_created_date.sk_secretariat_user_version, -1) AS sk_secretariat_on_sale_agreement_created,
    COALESCE(sa_sale_agreement_signed_date.sk_secretariat_user_version, -1) AS sk_secretariat_on_sale_agreement_signed,
    COALESCE(sa_last_secretariat.sk_secretariat_user_version, -1) AS sk_last_secretariat,
    COALESCE(bpt.sk_buyer_prospect_type, -1) AS sk_buyer_prospect_type,
    COALESCE(dsps_listing.sk_sale_price_segment, -1) AS sk_listing_price_segment,
    COALESCE(dsps_bp.sk_sale_price_segment, -1) AS sk_buyer_prospect_price_segment,
    COALESCE(CAST(REPLACE(SUBSTRING(eso.ts_offer_submitted,1, 10),'-','') AS BIGINT), -1) AS sk_offer_submitted_date,
    COALESCE(CAST(REPLACE(SUBSTRING(eso.dt_offer_accepted,1, 10),'-','') AS BIGINT), -1) AS sk_offer_accepted_date,
    COALESCE(CAST(REPLACE(SUBSTRING(eso.dt_offer_dismissed,1, 10),'-','') AS BIGINT), -1) AS sk_offer_dismissed_date,
    COALESCE(CAST(REPLACE(SUBSTRING(eso.dt_offer_rescued,1, 10),'-','') AS BIGINT), -1) AS sk_offer_rescued_date,
    COALESCE(CAST(REPLACE(SUBSTRING(eso.dt_sale_agreement_created,1, 10),'-','') AS BIGINT), -1) AS sk_sale_agreement_created_date,
    COALESCE(CAST(REPLACE(SUBSTRING(eso.dt_sale_agreement_signed,1, 10),'-','') AS BIGINT), -1) AS sk_sale_agreement_signed_date,
    COALESCE(CAST(REPLACE(SUBSTRING(eso.ts_seller_fup,1, 10),'-','') AS BIGINT), -1) AS sk_seller_fup_date,
    COALESCE(CAST(REPLACE(SUBSTRING(eso.ts_buyer_fup,1, 10),'-','') AS BIGINT), -1) AS sk_buyer_fup_date,
    eso.brokerage_fee,
    eso.sale_price_agreed,
    eso.has_used_fgts_in_payment,
    eso.is_buyer_first_offer,
    eso.is_house_first_offer,
    eso.flg_visit_completed_before_offer AS has_completed_visit_before_offer,
    eso.flg_booking_before_offer AS has_booking_before_offer,
    eso.first_price_offered_by_buyer,
    eso.last_price_offered_by_buyer,
    eso.first_discount_proposed,
    eso.last_discount_proposed,
    eso.days_offer_submitted_to_offer_accepted,
    eso.days_offer_submitted_to_offer_dismissed,
    eso.days_offer_submitted_to_sale_agreement_created,
    eso.days_offer_submitted_to_sale_agreement_signed,
    eso.days_offer_accepted_to_offer_dismissed,
    eso.days_offer_accepted_to_sale_agreement_created,
    eso.days_offer_accepted_to_sale_agreement_signed,
    eso.days_sale_agreement_created_to_sale_agreement_signed,
    eso.hours_booking_to_offer,
    eso.hours_visit_to_offer AS hours_visit_completed_to_offer,
    eso.ts_offer_submitted,
    eso.dt_offer_accepted::TIMESTAMP AS ts_offer_accepted,
    eso.dt_offer_dismissed::TIMESTAMP AS ts_offer_dismissed,
    eso.dt_offer_rescued::TIMESTAMP AS ts_offer_rescued,
    eso.dt_sale_agreement_created::TIMESTAMP AS ts_sale_agreement_created,
    eso.dt_sale_agreement_signed::TIMESTAMP AS ts_sale_agreement_signed,
    eso.ts_seller_fup,
    eso.ts_buyer_fup,
    NOW() AS ts_load
FROM
    datalake_offer.sale_offer AS eso
LEFT JOIN
    datalake_hub_services.daily_secretariat_allocation AS sa_creator
        ON sa_creator.id_secretariat_user = eso.id_user_secretariat_booking_creator
        AND sa_creator.dt_snapshot = DATE(eso.ts_booking_created)
LEFT JOIN
    datalake_hub_services.daily_secretariat_allocation AS sa_offer_submitted_date
        ON sa_offer_submitted_date.id_secretariat_user = eso.id_user_secretariat_on_offer_submitted_date
        AND sa_offer_submitted_date.dt_snapshot = DATE(eso.ts_offer_submitted)
LEFT JOIN
    datalake_hub_services.daily_secretariat_allocation AS sa_offer_accepted_date
        ON sa_offer_accepted_date.id_secretariat_user = eso.id_user_secretariat_on_offer_accepted_date
        AND sa_offer_accepted_date.dt_snapshot = DATE(eso.dt_offer_accepted)
LEFT JOIN
    datalake_hub_services.daily_secretariat_allocation AS sa_offer_dismissed_date
        ON sa_offer_dismissed_date.id_secretariat_user = eso.id_user_secretariat_on_offer_dismissed_date
        AND sa_offer_dismissed_date.dt_snapshot = DATE(eso.dt_offer_dismissed)
LEFT JOIN
    datalake_hub_services.daily_secretariat_allocation AS sa_sale_agreement_created_date
        ON sa_sale_agreement_created_date.id_secretariat_user = eso.id_user_secretariat_on_sale_agreement_created_date
        AND sa_sale_agreement_created_date.dt_snapshot = DATE(eso.dt_sale_agreement_created)
LEFT JOIN
    datalake_hub_services.daily_secretariat_allocation AS sa_sale_agreement_signed_date
        ON sa_sale_agreement_signed_date.id_secretariat_user = eso.id_user_secretariat_on_sale_agreement_signed_date
        AND sa_sale_agreement_signed_date.dt_snapshot = DATE(eso.dt_sale_agreement_signed)
LEFT JOIN
    datalake_hub_services.daily_secretariat_allocation AS sa_last_secretariat
        ON sa_last_secretariat.id_secretariat_user = eso.id_user_last_secretariat
        AND sa_last_secretariat.dt_snapshot = (CURRENT_DATE - INTERVAL '1' DAY)
LEFT JOIN datalake_region.region AS r
        ON eso.id_region = r.id
LEFT JOIN
    datalake_sale_listings.sale_listing_price_changes AS slpc
        ON eso.id_house = slpc.id_house
        AND eso.ts_offer_submitted >= slpc.ts_price_started 
        AND eso.ts_offer_submitted < COALESCE(slpc.ts_price_ended, NOW())
LEFT JOIN
    datalake_buyer_prospect.buyer_prospect_type AS bpt
        ON eso.id_buyer = bpt.id_prospect
        AND r.city_group = bpt.city_group
        AND COALESCE(eso.ts_booking_created, eso.ts_offer_submitted) >= bpt.ts_activation 
        AND COALESCE(eso.ts_booking_created, eso.ts_offer_submitted) < COALESCE(bpt.ts_activation_end, NOW())
LEFT JOIN
    dw_sale.dim_sale_price_segment AS dsps_listing
        ON slpc.price_segment = dsps_listing.price_segment
LEFT JOIN
    dw_sale.dim_sale_price_segment AS dsps_bp
        ON bpt.price_segment = dsps_bp.price_segment