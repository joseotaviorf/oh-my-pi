WITH demand_relation AS (
  SELECT
    bm.id_visit,
    bm.business_model,
    cs.sk_company
  FROM
    datalake_visit.visit_business_model AS bm
  LEFT JOIN
    datalake_ebdb_clean.visitor AS vt
      ON bm.id_visit = vt.id_visit
      AND vt.type = 'Agent'
  LEFT JOIN
    datalake_company.company_sks AS cs
      ON vt.uuid_company = cs.uuid_company
)
SELECT DISTINCT
  de.sk_sale_demand_event,
  de.sk_event_date,
  de.sk_event_type,
  de.sk_booking,
  de.sk_visit,
  de.sk_offer,
  de.sk_house,
  de.sk_region,
  de.sk_buyer,
  de.sk_seller,
  de.sk_agent,
  de.sk_agent_work_contract,
  de.sk_business_unit,
  de.sk_company_supply,
  dr.sk_company AS sk_company_demand,
  de.sk_secretariat_booking_creator,
  de.sk_secretariat_on_event,
  de.sk_last_secretariat,
  de.sk_buyer_prospect_type,
  de.sk_listing_price_segment,
  dr.business_model, 
  et.event_name AS event_name,
  et.abbreviation AS event_abbreviation,
  et.stage AS event_stage,
  dcs.company_name AS company_name_supply,
  dcs.hubspot_company_tag AS hubspot_company_tag_supply,
  dcd.company_name AS company_name_demand,
  dcd.hubspot_company_tag AS hubspot_company_tag_demand,
  dr.business_model LIKE '3P' AS has_3p_access_control,
  de.year,
  de.month,
  de.day,
  de.ts_event,
  de.ts_load
FROM
  dw_sale.fact_sale_demand_event AS de
LEFT JOIN
  dw_sale.dim_sale_event_type AS et
    ON et.sk_event_type = de.sk_event_type
LEFT JOIN
  demand_relation AS dr
    ON de.sk_visit = dr.id_visit
LEFT JOIN
  dw_public.dim_company_3p_partners AS dcs
    ON de.sk_company_supply = dcs.sk_company
LEFT JOIN
  dw_public.dim_company_3p_partners AS dcd
    ON dr.sk_company = dcd.sk_company