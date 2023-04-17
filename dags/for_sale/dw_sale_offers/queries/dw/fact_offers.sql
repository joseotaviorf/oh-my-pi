SELECT
	eso.id_offer AS sk_offer,
	eso.id_sale_flow AS sk_sale_flow,
	eso.id_house AS sk_house,
  	eso.id_buyer AS sk_buyer,
  	eso.id_owner AS sk_owner,
	COALESCE(eso.id_business_unit, -1) AS sk_business_unit,
	COALESCE(cs_supply.sk_company, -1) AS sk_company_supply,
	COALESCE(cs_demand.sk_company, -1) AS sk_company_demand,
	COALESCE(h.id_region,-1) AS sk_region,
  	COALESCE(eso.id_booking,-1) AS sk_booking,
  	COALESCE(eso.id_agent,-1) AS sk_agent,
	COALESCE(eso.id_user_agent, -1) AS sk_user_agent,
	COALESCE(eso.id_user_team_lead, -1) AS sk_user_team_lead,
	eso.id_user_consultant AS sk_user_consultant,
  	eso.id_consultant AS sk_consultant,
  	COALESCE(eso.id_closing_specialist, -1) AS sk_closing_specialist,
	COALESCE(CAST(REPLACE(SUBSTRING(eso.ts_offer_submitted,1, 10),'-','') AS BIGINT), -1) AS sk_offer_submitted_date,
	COALESCE(CAST(REPLACE(SUBSTRING(eso.dt_offer_accepted,1, 10),'-','') AS BIGINT), -1) AS sk_offer_accepted_date,
	COALESCE(CAST(REPLACE(SUBSTRING(eso.dt_offer_dismissed,1, 10),'-','') AS BIGINT), -1) AS sk_offer_dismissed_date,
	COALESCE(CAST(REPLACE(SUBSTRING(eso.dt_offer_rescued,1, 10),'-','') AS BIGINT), -1) AS sk_offer_rescued_date,
	COALESCE(CAST(REPLACE(SUBSTRING(eso.dt_sale_agreement_created,1, 10),'-','') AS BIGINT), -1) AS sk_sale_agreement_created_date,
	COALESCE(CAST(REPLACE(SUBSTRING(eso.dt_sale_agreement_signed,1, 10),'-','') AS BIGINT), -1) AS sk_sale_agreement_signed_date,
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
	NOW() AS ts_load
FROM
    datalake_offer.sale_offer AS eso
LEFT JOIN
    datalake_ebdb_clean.house AS h
        ON eso.id_house = h.id
LEFT JOIN
    datalake_rede_company.company_sks AS cs_demand
        ON (eso.id_company_demand IS NOT NULL
        AND eso.id_company_demand = cs_demand.id_hubspot)
        OR (eso.id_company_demand IS NULL
        AND eso.partner_3p_demand = cs_demand.extracted_3p_tag)
LEFT JOIN
    datalake_rede_company.company_sks AS cs_supply
        ON (eso.id_company_supply IS NOT NULL
        AND eso.id_company_supply = cs_supply.id_hubspot)
        OR (eso.id_company_supply IS NULL
        AND eso.partner_3p_supply = cs_supply.extracted_3p_tag)