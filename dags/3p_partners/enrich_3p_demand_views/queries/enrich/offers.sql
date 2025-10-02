WITH demand_relation AS (
  SELECT
    bm.id_visit,
    o.id_offer AS id_offer,
    cs.sk_company,
    bm.business_model
  FROM
    datalake_visit.visit_business_model AS bm
  LEFT JOIN
    datalake_ebdb_clean.visitor AS vt
      ON bm.id_visit = vt.id_visit
      AND vt.type = 'Agent'
  LEFT JOIN
    datalake_company.company_sks AS cs
      ON vt.uuid_company = cs.uuid_company
  LEFT JOIN
    datalake_booking.booking AS b
      ON b.id_visit = bm.id_visit
  LEFT JOIN
    datalake_sale_offer.sale_offer AS o
      ON b.id = o.id_booking
)
SELECT
  fo.sk_offer,
  fo.sk_sale_flow,
  fo.sk_booking,
  fo.sk_buyer,
  fo.sk_owner,
  fo.sk_house,
  fo.sk_user_agent,
  fo.sk_agent,
  fo.sk_consultant,
  fo.sk_user_consultant,
  fo.sk_closing_specialist,
  fo.sk_user_team_lead,
  fo.sk_business_unit,
  fo.sk_region,
  fo.sk_company_supply,
  dr.sk_company AS sk_company_demand,
  dr.business_model AS business_model,
  dcs.company_name AS company_name_supply,
  dcs.hubspot_company_tag AS hubspot_company_tag_supply,
  dcd.company_name AS company_name_demand,
  dcd.hubspot_company_tag AS hubspot_company_tag_demand,
  fo.is_buyer_first_offer,
  fo.is_house_first_offer,
  dr.business_model LIKE '3P' AS has_3p_access_control,
  fo.days_sale_agreement_created_to_sale_agreement_signed,
  fo.days_offer_accepted_to_sale_agreement_signed,
  fo.days_offer_accepted_to_sale_agreement_created,
  fo.days_offer_accepted_to_offer_dismissed,
  fo.days_offer_submitted_to_offer_accepted,
  fo.days_offer_submitted_to_sale_agreement_created,
  fo.days_offer_submitted_to_offer_dismissed,
  fo.days_offer_submitted_to_sale_agreement_signed,
  fo.hours_booking_to_offer,
  fo.ts_offer_submitted,
  fo.ts_offer_accepted,
  fo.ts_offer_dismissed,
  fo.ts_offer_rescued,
  fo.ts_sale_agreement_created,
  fo.ts_sale_agreement_signed,
  fo.ts_seller_fup,
  fo.ts_load
FROM
  dw_sale.fact_offers AS fo
LEFT JOIN
  demand_relation AS dr
    ON fo.sk_offer = dr.id_offer
LEFT JOIN
  dw_public.dim_company_3p_partners AS dcs
    ON fo.sk_company_supply = dcs.sk_company
LEFT JOIN
  dw_public.dim_company_3p_partners AS dcd
    ON dr.sk_company = dcd.sk_company
GROUP BY ALL