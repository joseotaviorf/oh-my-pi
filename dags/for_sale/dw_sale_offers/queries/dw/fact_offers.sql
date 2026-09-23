SELECT
    eso.id_offer AS sk_offer,
    eso.id_sales_flow AS sk_sales_flow,
    eso.id_house AS sk_house,
    eso.id_buyer AS sk_buyer,
    eso.id_owner AS sk_owner,
    COALESCE(eso.id_business_unit, -1) AS sk_business_unit,
    COALESCE(eso.sk_broker_supply, -1) AS sk_broker_supply,
    COALESCE(eso.sk_broker_demand, -1) AS sk_broker_demand,
    COALESCE(eso.id_region,-1) AS sk_region,
    COALESCE(eso.id_booking,-1) AS sk_booking,
    COALESCE(eso.id_agent,-1) AS sk_agent,
    COALESCE(eso.id_user_agent, -1) AS sk_user_agent,
    COALESCE(eso.id_user_team_lead, -1) AS sk_user_team_lead,
    eso.id_user_consultant AS sk_user_consultant,
    eso.id_consultant AS sk_consultant,
    COALESCE(eso.id_closing_specialist, -1) AS sk_closing_specialist,
    COALESCE(sa_creator.id_secretariat_user_version, -1) AS sk_secretariat_booking_creator,
    COALESCE(bpt.id_buyer_prospect_type, -1) AS sk_buyer_prospect_type,
    COALESCE(dsps_listing.sk_sale_price_segment, -1) AS sk_listing_price_segment,
    COALESCE(CAST(REPLACE(SUBSTRING(eso.ts_offer_submitted,1, 10),'-','') AS BIGINT), -1) AS sk_offer_submitted_date,
    COALESCE(CAST(REPLACE(SUBSTRING(eso.ts_offer_accepted,1, 10),'-','') AS BIGINT), -1) AS sk_offer_accepted_date,
    COALESCE(CAST(REPLACE(SUBSTRING(eso.ts_offer_dismissed,1, 10),'-','') AS BIGINT), -1) AS sk_offer_dismissed_date,
    COALESCE(CAST(REPLACE(SUBSTRING(eso.ts_offer_rescued,1, 10),'-','') AS BIGINT), -1) AS sk_offer_rescued_date,
    COALESCE(CAST(REPLACE(SUBSTRING(eso.ts_sale_agreement_created,1, 10),'-','') AS BIGINT), -1) AS sk_sale_agreement_created_date,
    COALESCE(CAST(REPLACE(SUBSTRING(eso.ts_sale_agreement_signed,1, 10),'-','') AS BIGINT), -1) AS sk_sale_agreement_signed_date,
    COALESCE(CAST(REPLACE(SUBSTRING(eso.ts_seller_fup,1, 10),'-','') AS BIGINT), -1) AS sk_seller_fup_date,
    COALESCE(CAST(REPLACE(SUBSTRING(eso.ts_buyer_fup,1, 10),'-','') AS BIGINT), -1) AS sk_buyer_fup_date,
    eso.brokerage_fee,
    eso.sale_price_agreed,
    eso.sale_type,
    eso.has_used_fgts_in_payment,
    eso.is_buyer_first_offer,
    eso.is_house_first_offer,
    eso.is_3p_supply,
    eso.is_3p_demand,
    eso.is_3p_lead_gen,
    eso.has_3p_access_control,
    eso.flg_visit_completed_before_offer AS has_completed_visit_before_offer,
    eso.flg_booking_before_offer AS has_booking_before_offer,
    eso.first_price_offered_by_buyer,
    eso.last_price_offered_by_buyer,
    eso.first_discount_proposed,
    eso.last_discount_proposed,
    eso.hours_booking_to_offer,
    eso.hours_visit_to_offer AS hours_visit_completed_to_offer,    
    eso.days_offer_submitted_to_offer_accepted,
    eso.days_offer_submitted_to_sale_agreement_created,
    eso.days_offer_submitted_to_offer_dismissed,
    eso.days_offer_submitted_to_sale_agreement_signed,
    eso.days_offer_accepted_to_sale_agreement_created,
    eso.days_offer_accepted_to_sale_agreement_signed,    
    eso.days_offer_accepted_to_offer_dismissed,
    eso.days_sale_agreement_created_to_sale_agreement_signed,
    eso.ts_offer_submitted,
    eso.ts_offer_accepted AS ts_offer_accepted,
    eso.ts_offer_dismissed AS ts_offer_dismissed,
    eso.ts_offer_canceled,
    eso.ts_offer_rescued AS ts_offer_rescued,
    eso.ts_sale_agreement_drafted,
    eso.ts_sale_agreement_created AS ts_sale_agreement_created,
    eso.ts_sale_agreement_signed AS ts_sale_agreement_signed,
    eso.ts_sale_agreement_canceled,
    eso.ts_seller_fup,
    eso.ts_buyer_fup,
    NOW() AS ts_load
FROM
    datalake_sale_offer.sale_offer AS eso    
LEFT JOIN
    datalake_secretariat.daily_secretariat_allocation AS sa_creator
        ON sa_creator.id_secretariat_user = eso.id_user_secretariat_booking_creator
        AND sa_creator.dt_snapshot = DATE(eso.ts_booking_created)
LEFT JOIN
  datalake_sale_listings.sale_listing_price_changes AS slpc
  ON  eso.id_house = slpc.id_house
  AND eso.ts_offer_submitted >= slpc.ts_price_started 
  AND eso.ts_offer_submitted < COALESCE(slpc.ts_price_ended, NOW())
LEFT JOIN
  datalake_buyer_prospect.buyer_prospect_type AS bpt
  ON eso.id_buyer = bpt.id_prospect
  AND eso.city_group = bpt.city_group
  AND eso.ts_offer_submitted >= bpt.ts_activation 
  AND eso.ts_offer_submitted < COALESCE(bpt.ts_activation_end, NOW())
LEFT JOIN
    dw_sale.dim_sale_price_segment AS dsps_listing
        ON slpc.price_segment = dsps_listing.price_segment