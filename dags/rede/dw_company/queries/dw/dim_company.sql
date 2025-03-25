SELECT
  cs.sk_company,
  cs.id_company,
  cs.uuid_company,
  COALESCE(a.city, 'Unknown') AS company_city,
  COALESCE(cs.cnpj, '-1') AS company_cnpj,
  COALESCE(a.country, 'Unknown') AS company_country,
  COALESCE(ci.company_name, 'Unknown') AS company_integrator_partner,
  c.company_name,
  COALESCE(cs.creci, '-1') AS company_creci,
  COALESCE(a.neighborhood, 'Unknown') AS company_neigborhood,
  COALESCE(a.state, 'Unknown') AS company_state,
  c.status AS company_status,
  c.trade_name AS company_trade_name,
  COALESCE(REGEXP_REPLACE(a.zip_code, '[^0-9]', ''), -1) AS company_zip_code,
  cs.is_company_asp,
  cs.is_company_ciq,
  cs.is_company_legal_person_rental_guarantee,
  cs.is_company_pp_multi,
  cs.is_company_rede_broker,
  cs.is_company_rental_guarantee,
  c.ts_created,
  c.ts_updated,
  NOW() AS ts_load
FROM
  datalake_company.company_sks AS cs
LEFT JOIN
  datalake_company_clean.company AS c
    ON cs.id_company = c.id
LEFT JOIN
  datalake_company_clean.address AS a
    ON cs.id_address = a.id
LEFT JOIN
  datalake_company_clean.company AS ci
    ON cs.uuid_integrator_partner = ci.uuid_company