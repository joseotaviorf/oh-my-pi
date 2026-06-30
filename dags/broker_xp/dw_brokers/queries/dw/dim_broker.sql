WITH broker_profiles AS (
  SELECT
    cp.sk_broker,
    COUNT(cp.sk_broker_profile) FILTER(WHERE cp.profile = 'third_party_agent') AS qt_active_agents,
    COUNT(cp.sk_broker_profile) FILTER(WHERE cp.profile = 'company_admin') AS qt_active_broker_admins
  FROM
    core_brokers.brokers_profile AS cp
  WHERE
    cp.profile_status = 'ACTIVE'
  GROUP BY
    cp.sk_broker
),
lead_gen_agents AS (
  SELECT
    ad.uuid_company,
    COUNT(ad.id) AS qt_active_agents_in_lead_gen
  FROM
    datalake_ebdb_clean.agent_data AS ad
  WHERE
    ad.agent_type = 'CORRETOR_REDE'
    AND ad.is_active
    AND ad.is_passive_lead_receiver
  GROUP BY
    ad.uuid_company
),
broker_membership AS (
  SELECT
    sk_broker,
    MAX(CASE WHEN broker_status = 'ACTIVE' THEN ts_start END) AS ts_last_membership_start,
    MAX(CASE WHEN broker_status = 'INACTIVE' AND is_current = true THEN ts_start END) AS ts_last_membership_end,
    MAX(CASE WHEN broker_status = 'ACTIVE' AND product_name = 'Rede Rent' THEN ts_start END) AS ts_last_rent_membership_start,
    MAX(CASE WHEN broker_status = 'INACTIVE' AND is_current = true AND product_name = 'Rede Rent' THEN ts_start END) AS ts_last_rent_membership_end,
    MAX(CASE WHEN broker_status = 'ACTIVE' AND product_name = 'Rede Sale' THEN ts_start END) AS ts_last_sale_membership_start,
    MAX(CASE WHEN broker_status = 'INACTIVE' AND is_current = true AND product_name = 'Rede Sale' THEN ts_start END) AS ts_last_sale_membership_end
  FROM
    datalake_brokers.broker_status_history
  GROUP BY
    sk_broker
),
broker_operation_areas AS (
  SELECT
    cbp.sk_broker,
    MAX(CASE WHEN COALESCE(cbp.general_region_list, '') <> '' THEN TRUE ELSE FALSE END) AS has_general_operation_area,
    MAX(CASE WHEN COALESCE(cbp.agent_region_list, '') <> '' THEN TRUE ELSE FALSE END) AS has_agent_operation_area,
    MAX(CASE WHEN cbp.business_context = 'RENT' AND COALESCE(cbp.general_region_list, '') <> '' THEN TRUE ELSE FALSE END) AS has_rent_general_operation_area,
    MAX(CASE WHEN cbp.business_context = 'RENT' AND COALESCE(cbp.agent_region_list, '') <> '' THEN TRUE ELSE FALSE END) AS has_rent_agent_operation_area,
    MAX(CASE WHEN cbp.business_context = 'SALE' AND COALESCE(cbp.general_region_list, '') <> '' THEN TRUE ELSE FALSE END) AS has_sale_general_operation_area,
    MAX(CASE WHEN cbp.business_context = 'SALE' AND COALESCE(cbp.agent_region_list, '') <> '' THEN TRUE ELSE FALSE END) AS has_sale_agent_operation_area
  FROM
    core_brokers.brokers_product AS cbp
  GROUP BY
    cbp.sk_broker
)
SELECT
  cb.sk_broker,
  cb.broker_name,
  cb.broker_trade_name,
  cb.broker_name_tag,
  cb.broker_trade_name_tag,
  ho.email AS account_manager,
  cb.broker_address,
  cb.broker_number,
  cb.broker_complement,
  cb.broker_city,
  cb.broker_state,
  cb.broker_country,
  cb.broker_zip_code,
  cb.creci,
  cb.cnpj,
  COALESCE(bp.qt_active_agents, 0) AS qt_active_agents,
  COALESCE(lga.qt_active_agents_in_lead_gen, 0) AS qt_active_agents_in_lead_gen,
  COALESCE(bp.qt_active_broker_admins, 0) AS qt_active_broker_admins,
  cb.is_3p_rent_broker,
  cb.is_3p_sale_broker,
  cb.is_3p_active_broker,
  cb.is_3p_active_rent_broker,
  cb.is_3p_active_sale_broker,
  lga.uuid_company IS NOT NULL AS has_active_agents_in_lead_gen,
  COALESCE(boa.has_general_operation_area, FALSE) AS has_general_operation_area,
  COALESCE(boa.has_agent_operation_area, FALSE) AS has_agent_operation_area,
  COALESCE(boa.has_rent_general_operation_area, FALSE) AS has_rent_general_operation_area,
  COALESCE(boa.has_rent_agent_operation_area, FALSE) AS has_rent_agent_operation_area,
  COALESCE(boa.has_sale_general_operation_area, FALSE) AS has_sale_general_operation_area,
  COALESCE(boa.has_sale_agent_operation_area, FALSE) AS has_sale_agent_operation_area,
  TRUE AS has_3p_access_control,
  bm.ts_last_membership_start,
  bm.ts_last_membership_end,
  bm.ts_last_rent_membership_start,
  bm.ts_last_rent_membership_end,
  bm.ts_last_sale_membership_start,
  bm.ts_last_sale_membership_end,
  aai.uuid_company IS NOT NULL AS is_alias_broker,
  aai.ts_phone_verified IS NOT NULL AS is_alias_active,
  aci.platform AS alias_crm_platform,
  ab.ts_created AS ts_alias_registered,
  cb.ts_broker_created,
  cb.ts_broker_updated,
  CURRENT_TIMESTAMP() AS ts_load,
  YEAR(cb.ts_broker_updated) AS year,
  MONTH(cb.ts_broker_updated) AS month,
  DAY(cb.ts_broker_updated) AS day
FROM
  core_brokers.brokers AS cb
LEFT JOIN
  datalake_brokers.hubspot_brokers_history AS hb
  ON cb.sk_broker = hb.sk_broker
  AND hb.is_current
LEFT JOIN
  datalake_hubspot.owner AS ho
  ON hb.id_hubspot_owner = ho.id_owner
LEFT JOIN
  broker_profiles AS bp
  ON cb.sk_broker = bp.sk_broker
LEFT JOIN
  lead_gen_agents AS lga
  ON lga.uuid_company = cb.uuid_company
LEFT JOIN
  broker_membership AS bm
  ON bm.sk_broker = cb.sk_broker
LEFT JOIN
  broker_operation_areas AS boa
  ON boa.sk_broker = cb.sk_broker
LEFT JOIN
  datalake_alias_clean.ai_agents AS aai
  ON aai.uuid_company = cb.uuid_company
LEFT JOIN
  datalake_alias_clean.crm_integrations AS aci
  ON aci.uuid_company = cb.uuid_company
LEFT JOIN
  datalake_alias_clean.brokers AS ab
  ON ab.uuid_company = cb.uuid_company