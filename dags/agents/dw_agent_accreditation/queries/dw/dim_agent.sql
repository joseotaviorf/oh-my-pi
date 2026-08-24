WITH agent_lead_referral AS (
  SELECT
    alr.id_agent AS id_agent_data,
    COALESCE(BOOL_OR((alr.business_context = 'SALE' OR alr.business_context IS NULL) AND alr.status <> 'NOT_ELIGIBLE'), FALSE) AS has_sale_lead_referral,
    COALESCE(BOOL_OR((alr.business_context = 'SALE' OR alr.business_context IS NULL) AND alr.status = 'CONFIRMED'), FALSE) AS has_sale_lead_referral_confirmed,
    COALESCE(BOOL_OR(alr.business_context = 'RENT' AND alr.status <> 'NOT_ELIGIBLE'), FALSE) AS has_rent_lead_referral,
    COALESCE(BOOL_OR(alr.business_context = 'RENT' AND alr.status = 'CONFIRMED'), FALSE) AS has_rent_lead_referral_confirmed
  FROM
    datalake_ebdb_clean.agent_lead_referral AS alr
  GROUP BY
    alr.id_agent
)
SELECT
  a.id_agent AS sk_agent,
  a.id_agent_data AS sk_agent_data,
  a.id_partner AS sk_partner,
  a.id_user AS sk_user,
  COALESCE(cb.sk_broker, -1) AS sk_broker,
  a.uuid_company,
  a.uuid_agent,
  a.uuid_person,
  a.creci,
  a.creci_uf,
  a.affiliation_type,
  a.status,
  product.product_name AS profile,
  product.deactivation_reason,
  product.deactivation_sub_reason,
  a.is_reactivated,
  a.is_allow_supply_acquisition,
  a.is_allow_demand_acquisition,
  a.is_allow_visit,
  a.is_allow_demand_sale,
  a.is_allow_demand_rent,
  a.is_passive_lead_receiver,
  a.is_1p_partnership,
  a.is_3p_partnership,
  COALESCE(alr.has_rent_lead_referral, FALSE) AS has_rent_lead_referral,
  COALESCE(alr.has_rent_lead_referral_confirmed, FALSE) AS has_rent_lead_referral_confirmed,
  COALESCE(alr.has_sale_lead_referral, FALSE) AS has_sale_lead_referral,
  COALESCE(alr.has_sale_lead_referral_confirmed, FALSE) AS has_sale_lead_referral_confirmed,
  a.days_in_current_status,
  a.ts_last_status_changed,
  a.ts_created,
  a.ts_updated
FROM
  datalake_agent_accreditation.agent AS a
LEFT JOIN
  core_brokers.brokers AS cb
    ON a.uuid_company = cb.uuid_company
    AND a.is_3p_partnership = TRUE
LEFT JOIN
  agent_lead_referral AS alr
    ON a.id_agent_data = alr.id_agent_data
LEFT JOIN
  datalake_ebdb_agent_events.agent_product AS product
    ON a.id_agent = product.id_agent
    AND product.is_valid_product IS TRUE
    AND product.is_lastest_valid IS TRUE