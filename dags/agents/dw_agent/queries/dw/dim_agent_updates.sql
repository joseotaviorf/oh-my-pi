WITH audit_with_previous AS (
  SELECT
-- Previous values using LAG
    aud.id,
    aud.rev,
    aud.rev_type,
    aud.id_work_contract,
    aud.id_preferred_region,
    aud.uuid_company,
    aud.profile,
    aud.agent_type,
    aud.position_in_real_estate_agency,
    aud.real_estate_agency,
    aud.creci_number,
    aud.code,
    aud.is_active,
    aud.is_blocked_schedule_edition,
    aud.is_passive_lead_receiver,
    aud.is_service_link_active,
    aud.has_opted_for_online_support,
    LAG(aud.id_work_contract) OVER (PARTITION BY aud.id ORDER BY aud.rev) AS prev_id_work_contract,
    LAG(aud.id_preferred_region) OVER (PARTITION BY aud.id ORDER BY aud.rev) AS prev_id_preferred_region,
    LAG(aud.uuid_company) OVER (PARTITION BY aud.id ORDER BY aud.rev) AS prev_uuid_company,
    LAG(aud.profile) OVER (PARTITION BY aud.id ORDER BY aud.rev) AS prev_profile,
    LAG(aud.agent_type) OVER (PARTITION BY aud.id ORDER BY aud.rev) AS prev_agent_type,
    LAG(aud.position_in_real_estate_agency) OVER (PARTITION BY aud.id ORDER BY aud.rev) AS prev_position_in_real_estate_agency,
    LAG(aud.real_estate_agency) OVER (PARTITION BY aud.id ORDER BY aud.rev) AS prev_real_estate_agency,
    LAG(aud.creci_number) OVER (PARTITION BY aud.id ORDER BY aud.rev) AS prev_creci_number,
    LAG(aud.code) OVER (PARTITION BY aud.id ORDER BY aud.rev) AS prev_code,
    LAG(aud.is_active) OVER (PARTITION BY aud.id ORDER BY aud.rev) AS prev_is_active,
    LAG(aud.is_blocked_schedule_edition) OVER (PARTITION BY aud.id ORDER BY aud.rev) AS prev_is_blocked_schedule_edition,
    LAG(aud.is_passive_lead_receiver) OVER (PARTITION BY aud.id ORDER BY aud.rev) AS prev_is_passive_lead_receiver,
    LAG(aud.is_service_link_active) OVER (PARTITION BY aud.id ORDER BY aud.rev) AS prev_is_service_link_active,
    LAG(aud.has_opted_for_online_support) OVER (PARTITION BY aud.id ORDER BY aud.rev) AS prev_has_opted_for_online_support,
    ROW_NUMBER() OVER (PARTITION BY aud.id ORDER BY aud.rev) AS row_num
  FROM
    datalake_ebdb_clean.agent_data_aud AS aud
),
unpivoted_all AS (
-- Unpivot all attributes dynamically
  SELECT
    ap.id,
    ap.rev,
    ap.rev_type,
    ap.row_num,
    unp.attribute_name,
    unp.attribute_value,
    unp.prev_attribute_value
  FROM
    audit_with_previous AS ap,
  LATERAL STACK (
    14,
    'id_work_contract', CAST(ap.id_work_contract AS STRING), CAST(ap.prev_id_work_contract AS STRING),
    'id_preferred_region', CAST(ap.id_preferred_region AS STRING), CAST(ap.prev_id_preferred_region AS STRING),
    'uuid_company', CAST(ap.uuid_company AS STRING), CAST(ap.prev_uuid_company AS STRING),
    'profile', CAST(ap.profile AS STRING), CAST(ap.prev_profile AS STRING),
    'agent_type', CAST(ap.agent_type AS STRING), CAST(ap.prev_agent_type AS STRING),
    'position_in_real_estate_agency', CAST(ap.position_in_real_estate_agency AS STRING), CAST(ap.prev_position_in_real_estate_agency AS STRING),
    'real_estate_agency', CAST(ap.real_estate_agency AS STRING), CAST(ap.prev_real_estate_agency AS STRING),
    'creci_number', CAST(ap.creci_number AS STRING), CAST(ap.prev_creci_number AS STRING),
    'code', CAST(ap.code AS STRING), CAST(ap.prev_code AS STRING),
    'is_active', CAST(ap.is_active AS STRING), CAST(ap.prev_is_active AS STRING),
    'is_blocked_schedule_edition', CAST(ap.is_blocked_schedule_edition AS STRING), CAST(ap.prev_is_blocked_schedule_edition AS STRING),
    'is_passive_lead_receiver', CAST(ap.is_passive_lead_receiver AS STRING), CAST(ap.prev_is_passive_lead_receiver AS STRING),
    'is_service_link_active', CAST(ap.is_service_link_active AS STRING), CAST(ap.prev_is_service_link_active AS STRING),
    'has_opted_for_online_support', CAST(ap.has_opted_for_online_support AS STRING), CAST(ap.prev_has_opted_for_online_support AS STRING)
  ) AS unp (attribute_name, attribute_value, prev_attribute_value)
  WHERE
-- Remove delete operations
    ap.rev_type != 2
),
unpivoted_changes AS (
  SELECT
    ua.id,
    ua.rev,
    ua.rev_type,
    ua.attribute_name,
    ua.attribute_value
  FROM
    unpivoted_all AS ua
  WHERE
    ua.row_num = 1 OR NOT (ua.attribute_value != ua.prev_attribute_value)
),
changes_with_timestamp AS (
  SELECT
    uc.id,
    uc.rev,
    uc.rev_type,
    uc.attribute_name,
    uc.attribute_value,
    ure.ts_revision,
    ure.id_user AS id_user_change,
    ure.reason AS change_reason
  FROM
    unpivoted_changes AS uc
  INNER JOIN
    datalake_ebdb_clean.user_revision_entity AS ure
      ON uc.rev = ure.id
),
changes_with_intervals AS (
  SELECT
    cwt.id,
    cwt.rev,
    cwt.rev_type,
    cwt.attribute_name,
    cwt.attribute_value,
    cwt.ts_revision AS ts_start,
    LEAD(cwt.ts_revision) OVER (PARTITION BY cwt.id, cwt.attribute_name ORDER BY cwt.rev) AS ts_end,
    ROW_NUMBER() OVER (PARTITION BY cwt.id, cwt.attribute_name ORDER BY cwt.rev) AS version_number
  FROM
    changes_with_timestamp AS cwt
)
SELECT
  XXHASH64(ci.id, ci.attribute_name, ci.version_number, ci.ts_start, COALESCE(ci.ts_end, 0)) AS sk_agent_update,
  ci.id AS sk_agent,
  COALESCE(c.sk_company, -1) AS sk_company,
  ci.attribute_name,
  ci.attribute_value,
  ci.version_number,
  ci.ts_end IS NULL AS is_current,
  DATE_FORMAT(TIMESTAMP_MILLIS(ci.ts_start), 'yyyy-MM-dd HH:mm:ss.SSS+00:00') AS ts_start,
  DATE_FORMAT(TIMESTAMP_MILLIS(ci.ts_end), 'yyyy-MM-dd HH:mm:ss.SSS+00:00') AS ts_end,
  NOW() AS ts_load
FROM
  changes_with_intervals AS ci
LEFT JOIN
  datalake_company.company_sks AS c
    ON c.uuid_company = ci.attribute_value