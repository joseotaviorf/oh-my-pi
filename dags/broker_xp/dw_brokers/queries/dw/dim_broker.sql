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
  GROUP BY ALL
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
)
SELECT
  cb.sk_broker,
  COALESCE(p.sk_person, -1) AS sk_person_account_manager,
  cb.broker_name,
  cb.broker_trade_name,
  cb.broker_name_tag,
  cb.broker_trade_name_tag,
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
  TRUE AS has_3p_access_control,
  bm.ts_last_membership_start,
  bm.ts_last_membership_end,
  bm.ts_last_rent_membership_start,
  bm.ts_last_rent_membership_end,
  bm.ts_last_sale_membership_start,
  bm.ts_last_sale_membership_end,
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
LEFT JOIN
  lead_gen_agents AS lga
  ON lga.uuid_company = cb.uuid_company
LEFT JOIN
  broker_membership AS bm
  ON bm.sk_broker = cb.sk_broker