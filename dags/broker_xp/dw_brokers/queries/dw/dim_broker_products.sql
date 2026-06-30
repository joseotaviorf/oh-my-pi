SELECT
  cbp.sk_broker_product,
  cbp.sk_broker,
  cbp.product_name,
  cbp.business_segment,
  cbp.product_status,
  cbp.business_context,
  cbp.integrator_partner,
  cbp.integrator_partner_status,
  cbp.commission,
  cbp.demand_fee,
  cbp.supply_fee,
  cbp.platform_fee,
  cbp.bank,
  cbp.agency_number,
  cbp.account_number,
  cbp.account_type,
  cbp.tier_name,
  cbp.is_3p_rent_broker,
  cbp.is_3p_sale_broker,
  cbp.is_3p_active_broker,
  cbp.is_3p_active_rent_broker,
  cbp.is_3p_active_sale_broker,
  cbp.has_opt_in_navent,
  COALESCE(cbp.general_region_list, '') <> '' AS has_general_operation_area,
  COALESCE(cbp.agent_region_list, '') <> '' AS has_agent_operation_area,
  aci.platform AS crm_platform,
  TRUE AS has_3p_access_control,
  cbp.ts_product_created,
  cbp.ts_product_updated,
  CURRENT_TIMESTAMP() AS ts_load,
  YEAR(cbp.ts_product_updated) AS year,
  MONTH(cbp.ts_product_updated) AS month,
  DAY(cbp.ts_product_updated) AS day
FROM
  core_brokers.brokers_product AS cbp
LEFT JOIN datalake_alias_clean.crm_integrations AS aci
  ON cbp.uuid_company = aci.uuid_company
  AND cbp.business_context = 'ALIAS'