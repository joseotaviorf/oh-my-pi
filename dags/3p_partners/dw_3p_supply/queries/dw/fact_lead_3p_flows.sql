SELECT
  CASE
    WHEN lsc.business_context = 'SALE' THEN l.id_lead_3p * 10
    WHEN lsc.business_context = 'RENT' THEN l.id_lead_3p * 10 + 1
  END AS sk_lead_3p_flow,
  l.id_lead_3p AS sk_lead_3p,
  COALESCE(l.region_id, -1) AS sk_region,
  COALESCE(l.id_house, -1) AS sk_house,
  COALESCE(lsc.id_duplicated_house, -1) AS sk_house_duplicated,
  COALESCE(ps.sk_person, -1) AS sk_person_owner_agent,
  COALESCE(cb.sk_broker, -1) AS sk_broker,
  COALESCE(cs.sk_company, -1) AS sk_company,
  l.lead_hash,
  lsc.business_context,
  flpc.is_valid_lead_occurrence,
  lsc.is_opportunity,
  lsc.is_eligible_pending,
  lsc.is_not_eligible_pending,
  lds.is_first_listing_published_through_portfolio_manager,
  l.has_lead_house_conflicts,
  l.has_3p_access_control,
  lsc.ts_unpublished_in_bsp,
  lsc.ts_discarded_in_bsp,
  lsc.ts_suspended_in_bsp,
  lsc.ts_first_not_converted_in_bsp,
  lsc.ts_last_not_converted_in_bsp,
  lsc.ts_first_processing_photos_in_bsp,
  lsc.ts_last_processing_photos_in_bsp,
  lsc.ts_first_registered_from_bsp_to_main,
  lds.ts_availability_start AS ts_availability_check_start,
  lds.ts_availability_end AS ts_availability_check_end,
  lds.ts_first_listing,
  l.ts_lead_created,
  l.ts_lead_updated,
  lsc.ts_business_context_created,
  CURRENT_TIMESTAMP() AS ts_load,
  YEAR(lsc.ts_start) AS year,
  MONTH(lsc.ts_start) AS month,
  DAY(lsc.ts_start) AS day
FROM
  datalake_3p_supply.lead_3p AS l
LEFT JOIN
  datalake_3p_supply.lead_3p_status_changes AS lsc
  ON l.id_lead_3p = lsc.id_lead_3p
  AND lsc.is_current = TRUE
LEFT JOIN
  datalake_3p_supply.listing_draft_status AS lds
  ON l.id_house = lds.id_house
  AND lsc.business_context = lds.business_context
LEFT JOIN
  core_brokers.brokers AS cb
  ON l.uuid_company = cb.uuid_company
LEFT JOIN
  datalake_3p_supply.first_lead_per_contract AS flpc
  ON l.id_lead_3p = flpc.id_lead_3p
  AND lsc.business_context = flpc.business_context
LEFT JOIN
  datalake_company.company_sks AS cs
  ON l.uuid_company = cs.uuid_company
LEFT JOIN
  datalake_person.person_sks AS ps
  ON l.owner_agent_person_uuid = ps.uuid_person
