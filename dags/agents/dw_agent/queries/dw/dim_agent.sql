SELECT
  ad.id AS sk_agent,
  COALESCE(p.sk_person, -1) AS sk_person,
  COALESCE(u.id, -1) AS sk_user,
  COALESCE(c.sk_company, -1) AS sk_company,
  u.id AS id_user,
  ad.code AS agent_code,
  ad.profile AS agent_profile,
  at.types AS agent_type,
  ad.agent_type AS agent_type_main,
  REGEXP_REPLACE(wc.contract_name, '[\\[\\]]', '') AS contract_name,
  ad.creci_number,
  c.extracted_3p_tag AS rede_partner,
  ad.is_active AS is_agent_active,
  u.is_active AS is_user_active,
  u.is_blocked,
  ad.agent_type = 'CORRETOR_REDE' AS is_3p_agent,
  ead.is_rent_agent,
  ead.is_sale_agent,
  af.is_active AS is_affiliate_active,
  ph.is_active AS is_photographer_active,
  u.is_tenant,
  ad.is_passive_lead_receiver,
  ad.is_service_link_active,
  mp.status = 'ACTIVE' AS has_3p_member_profile_active,
  mp.status IN ('PENDING CONFIRMATION', 'PENDING INVITATION') AS has_3p_member_profile_pending,
  ad.ts_created,
  ad.ts_updated,
  NOW() AS ts_load
FROM
  datalake_ebdb_clean.agent_data AS ad
LEFT JOIN
  datalake_ebdb_user.agent_data AS ead
    ON ad.id = ead.id
LEFT JOIN
  datalake_ebdb_user.user AS u
    ON ad.id = u.id_agent
LEFT JOIN
  datalake_ebdb_user.affiliate_data AS af
    ON af.id = u.id_affiliates
LEFT JOIN
  datalake_ebdb_clean.photographer_data AS ph
    ON ph.id = u.id_photographer_data
LEFT JOIN
  datalake_ebdb_clean.agent_data_types AS at
    ON at.id_agent_data = ad.id
LEFT JOIN
  datalake_ebdb_clean.work_contract AS wc
    ON wc.id = ad.id_work_contract
LEFT JOIN
  datalake_person.person_sks AS p
    ON p.uuid_person = u.uuid_person
LEFT JOIN
  datalake_company.company_sks AS c
    ON ad.uuid_company = c.uuid_company
LEFT JOIN
  datalake_company_clean.member_profile AS mp
    ON p.uuid_person = mp.uuid_person
    AND c.id_company = mp.id_company
    AND mp.id_profile = 17 -- 3P agent profile in company service
    AND mp.id_product = 27 -- 3P real estate product in company service
QUALIFY -- There are extremely few duplicate rows on agent_data_types (12/16595 at the moment of writing). This is to get rid of them.
  ROW_NUMBER() OVER(PARTITION BY ad.id ORDER BY at.types) = 1