WITH broker_profiles AS (
  SELECT
    cp.sk_broker,
    COUNT(cp.sk_broker_profile) FILTER(WHERE cp.profile = 'third_party_agent') AS qt_active_agents,
    COUNT(cp.sk_broker_profile) FILTER(WHERE cp.profile = 'third_party_agent' AND cp.business_context = 'SALE') AS qt_active_sale_agents,
    COUNT(cp.sk_broker_profile) FILTER(WHERE cp.profile = 'third_party_agent' AND cp.business_context = 'RENT') AS qt_active_rent_agents,
    COUNT(cp.sk_broker_profile) FILTER(WHERE cp.profile = 'company_admin') AS qt_active_broker_admins
  FROM
    core_brokers.brokers_profile AS cp
  WHERE
    cp.profile_status = 'ACTIVE'
  GROUP BY
    cp.sk_broker
)
SELECT
  cb.sk_broker,
  COALESCE(p.sk_person, -1) AS sk_person_account_manager,
  cb.broker_name,
  cb.broker_trade_name,
  cb.broker_status,
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
  COALESCE(bp.qt_active_sale_agents, 0) AS qt_active_sale_agents,
  COALESCE(bp.qt_active_rent_agents, 0) AS qt_active_rent_agents,
  COALESCE(bp.qt_active_broker_admins, 0) AS qt_active_broker_admins,
  cb.is_3p_rent_broker,
  cb.is_3p_sale_broker,
  cb.is_3p_active_broker,
  cb.is_3p_active_rent_broker,
  cb.is_3p_active_sale_broker,
  TRUE AS has_3p_access_control,
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
  datalake_person.person_sks AS p
  ON ho.uuid_person = p.uuid_person
LEFT JOIN
  broker_profiles AS bp
  ON cb.sk_broker = bp.sk_broker