SELECT
  psk.sk_person,
  psk.id_person,
  psk.id_user,
  IF(ENDSWITH(cie.contact_info, '@quintoandar.com.br'), SPLIT(cie.contact_info, '@')[0], NULL) AS id_user_email,
  psk.uuid_person,
  COALESCE(p.country_code, 'Unknown') AS country_code,
  COALESCE(ps.language, 'Unknown') AS language,
  COALESCE(cie.contact_info, 'Unknown') AS person_email,
  p.person_name,
  COALESCE(REGEXP_REPLACE(cip.contact_info, '[^0-9]', ''), '-1') AS person_phone,
  COALESCE(ps.timezone, 'Unknown') AS timezone,
  p.is_blocked,
  rf.id_person IS NOT NULL AS has_right_to_be_forgotten,
  psk.has_affiliated_member_profile,
  psk.has_buyer_prospect_member_profile,
  psk.has_ciq_member_profile,
  psk.has_company_admin_member_profile,
  psk.has_company_owner_member_profile,
  psk.has_company_member_profile,
  psk.has_contract_person_member_profile,
  psk.has_customer_member_profile,
  psk.has_legal_person_tenant_member_profile,
  psk.has_partner_agent_member_profile,
  psk.has_photographer_agent_member_profile,
  psk.has_photographer_member_profile,
  psk.has_property_inspector_member_profile,
  psk.has_property_owner_member_profile,
  psk.has_property_owner_prospect_member_profile,
  psk.has_realtor_member_profile,
  psk.has_tenant_member_profile,
  psk.has_tenant_prospect_member_profile,
  psk.has_third_party_agent_member_profile,
  p.dt_birth AS dt_person_birth,
  p.ts_created,
  p.ts_updated,
  NOW() AS ts_load
FROM
  datalake_person.person_sks AS psk
JOIN
  datalake_person_clean.person AS p
    ON psk.id_person = p.id
LEFT JOIN
  datalake_person_clean.contact_info AS cie
    ON cie.id = psk.id_contact_info_email
LEFT JOIN
  datalake_person_clean.contact_info AS cip
    ON cip.id = psk.id_contact_info_phone
LEFT JOIN
  datalake_person_clean.preference_settings AS ps
    ON ps.id = psk.id_preference_settings
LEFT JOIN
  datalake_person_clean.right_to_be_forgotten AS rf
    ON rf.id = psk.id_right_to_be_forgotten