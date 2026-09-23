SELECT
  lsc.sk_lead_3p_flow,
  l.id_lead_3p AS sk_lead_3p,
  COALESCE(lds.sk_listing_draft_status, -1) AS sk_listing_draft_status,
  COALESCE(l.region_id, -1) AS sk_region,
  COALESCE(l.id_house, -1) AS sk_house,
  COALESCE(lsc.sk_house_duplicated, -1) AS sk_house_duplicated,
  COALESCE(ps.sk_person, -1) AS sk_person_owner_agent,
  COALESCE(cb.sk_broker, -1) AS sk_broker,
  l.id_by_real_estate,
  l.lead_hash,
  lsc.business_context,
  lsc.is_opportunity,
  lsc.is_eligible_pending,
  lsc.is_not_eligible_pending,
  lds.is_first_listing_published_through_portfolio_manager,
  blr.is_valid_first_lead,
  blr.is_current_valid_first_lead,
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
  lds.ts_availability_check_start,
  lds.ts_availability_check_end,
  lds.ts_first_listing,
  blr.ts_partner_contract_start,
  blr.ts_valid_first_lead,
  blr.ts_current_valid_first_lead,
  l.ts_lead_created,
  l.ts_lead_updated,
  lsc.ts_business_context_created,
  CURRENT_TIMESTAMP() AS ts_load,
  YEAR(lsc.ts_start) AS year,
  MONTH(lsc.ts_start) AS month,
  DAY(lsc.ts_start) AS day
FROM
  datalake_3p_supply.lead_3p AS l
-- The grain is the lead flow, so a fact row requires a current status carrying a
-- surrogate key. A lead with no business context, or one whose context has no branch
-- in the sk_lead_3p_flow mapping, would land here with a NULL primary key and NULL
-- partitions. Those leads remain available in dim_lead_3p, which is at lead grain.
INNER JOIN
  datalake_3p_supply.lead_3p_status_changes AS lsc
  ON l.id_lead_3p = lsc.id_lead_3p
  AND lsc.is_current = TRUE
  AND NOT lsc.sk_lead_3p_flow IS NULL
LEFT JOIN
  datalake_3p_supply.listing_draft_status AS lds
  ON l.id_house = lds.id_house
  AND lsc.business_context = lds.business_context
LEFT JOIN
  core_brokers.brokers AS cb
  ON l.uuid_company = cb.uuid_company
LEFT JOIN
  datalake_3p_supply.broker_lead_relationship AS blr
  ON lsc.sk_lead_3p_flow = blr.sk_lead_3p_flow
LEFT JOIN
  datalake_person.person_sks AS ps
  ON l.owner_agent_person_uuid = ps.uuid_person
