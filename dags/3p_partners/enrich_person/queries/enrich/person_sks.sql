WITH contact_info_email AS (
  SELECT
    ci.id AS id_contact_info_email,
    ci.id_person
  FROM
    datalake_person_clean.contact_info AS ci
  WHERE
    ci.category = 'EMAIL'
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY ci.id_person ORDER BY ci.ts_updated DESC) = 1
),
contact_info_phone AS (
  SELECT
    ci.id AS id_contact_info_phone,
    ci.id_person
  FROM
    datalake_person_clean.contact_info AS ci
  WHERE
    ci.category = 'PHONE'
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY ci.id_person ORDER BY ci.ts_updated DESC) = 1
),
main_user AS (
  SELECT
    cr.id_person,
    cr.id_reference AS id_user
  FROM
    datalake_person_clean.credential_reference AS cr
  WHERE
    cr.origin = 'main'
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY cr.id_person ORDER BY cr.ts_updated DESC) = 1
),
right_to_be_forgotten AS (
  SELECT
    rf.id AS id_right_to_be_forgotten,
    rf.id_person
  FROM
    datalake_person_clean.right_to_be_forgotten AS rf
  QUALIFY
      ROW_NUMBER() OVER(PARTITION BY rf.id_person ORDER BY rf.ts_updated DESC) = 1
),
member_profile AS (
  SELECT
    mp.uuid_person,
    MAX(mp.id_profile) = 5 AS has_affiliated_member_profile,
    MAX(mp.id_profile) = 11 AS has_buyer_prospect_member_profile,
    MAX(mp.id_profile) = 2 AS has_ciq_member_profile,
    MAX(mp.id_profile) = 13 AS has_company_admin_member_profile,
    MAX(mp.id_profile) = 6 AS has_company_owner_member_profile,
    MAX(mp.id_profile) = 19 AS has_company_member_profile,
    MAX(mp.id_profile) = 12 AS has_contract_person_member_profile,
    MAX(mp.id_profile) = 8 AS has_customer_member_profile,
    MAX(mp.id_profile) = 15 AS has_legal_person_tenant_member_profile,
    MAX(mp.id_profile) = 18 AS has_partner_agent_member_profile,
    MAX(mp.id_profile) = 16 AS has_photographer_agent_member_profile,
    MAX(mp.id_profile) = 4 AS has_photographer_member_profile,
    MAX(mp.id_profile) = 3 AS has_property_inspector_member_profile,
    MAX(mp.id_profile) = 7 AS has_property_owner_member_profile,
    MAX(mp.id_profile) = 14 AS has_property_owner_prospect_member_profile,
    MAX(mp.id_profile) = 1 AS has_realtor_member_profile,
    MAX(mp.id_profile) = 9 AS has_tenant_member_profile,
    MAX(mp.id_profile) = 10 AS has_tenant_prospect_member_profile,
    MAX(mp.id_profile) = 17 AS has_third_party_agent_member_profile
  FROM
    datalake_company_clean.member_profile AS mp
  GROUP BY
    ALL
)
SELECT
  XXHASH64(p.id) AS sk_person,
  p.id AS id_person,
  cie.id_contact_info_email,
  cip.id_contact_info_phone,
  ps.id AS id_preference_settings,
  rf.id_right_to_be_forgotten,
  mu.id_user,
  p.uuid_person,
  mp.has_affiliated_member_profile,
  mp.has_buyer_prospect_member_profile,
  mp.has_ciq_member_profile,
  mp.has_company_admin_member_profile,
  mp.has_company_owner_member_profile,
  mp.has_company_member_profile,
  mp.has_contract_person_member_profile,
  mp.has_customer_member_profile,
  mp.has_legal_person_tenant_member_profile,
  mp.has_partner_agent_member_profile,
  mp.has_photographer_agent_member_profile,
  mp.has_photographer_member_profile,
  mp.has_property_inspector_member_profile,
  mp.has_property_owner_member_profile,
  mp.has_property_owner_prospect_member_profile,
  mp.has_realtor_member_profile,
  mp.has_tenant_member_profile,
  mp.has_tenant_prospect_member_profile,
  mp.has_third_party_agent_member_profile,
  p.ts_created,
  p.ts_updated
FROM
  datalake_person_clean.person AS p
LEFT JOIN
  contact_info_email AS cie
    ON p.id = cie.id_person
LEFT JOIN
  contact_info_phone AS cip
    ON p.id = cip.id_person
LEFT JOIN
  main_user AS mu
    ON p.id = mu.id_person
LEFT JOIN
  datalake_person_clean.preference_settings AS ps
    ON p.id = ps.id_person
LEFT JOIN
  right_to_be_forgotten AS rf
    ON p.id = rf.id_person
LEFT JOIN
  member_profile AS mp
    ON p.uuid_person = mp.uuid_person
GROUP BY
  ALL