SELECT
  bp.sk_broker_profile,
  COALESCE(bp.sk_broker, -1) AS sk_broker,
  COALESCE(ps.sk_person, -1) AS sk_person,
  bp.profile,
  bp.profile_status,
  bp.profile_status = 'ACTIVE' AS is_active_profile,
  bp.profile = 'third_party_agent' AS is_agent,
  bp.profile = 'company_admin' AS is_broker_admin,
  LEAD(bp.ts_profile_created) OVER (PARTITION BY bp.uuid_person, bp.profile ORDER BY bp.ts_profile_created) IS NULL AS is_current,
  TRUE AS has_3p_access_control,
  bp.ts_profile_created AS ts_start,
  LEAD(bp.ts_profile_created) OVER (PARTITION BY bp.uuid_person, bp.profile ORDER BY bp.ts_profile_created) AS ts_end,
  CURRENT_TIMESTAMP() AS ts_load,
  YEAR(bp.ts_profile_created) AS year,
  MONTH(bp.ts_profile_created) AS month,
  DAY(bp.ts_profile_created) AS day
FROM
  core_brokers.brokers_profile AS bp
LEFT JOIN
  datalake_person.person_sks AS ps
    ON bp.uuid_person = ps.uuid_person