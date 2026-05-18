-- Tab Partners_PF — datalake_gsheets_raw.ind_agents_partner_allocation (headers normalized to snake_case).

SELECT
  TRY_CAST(TRIM(sk_agent) AS BIGINT) AS id_agent,
  TRY_CAST(TRIM(sk_user) AS BIGINT) AS id_user,
  TRIM(imobiliaria) AS real_estate_agency_name,
  TRY_CAST(NULLIF(TRIM(contact_started), '') AS DATE) AS dt_contact_started,
  TRY_CAST(NULLIF(TRIM(contract_ended), '') AS DATE) AS dt_contract_ended,
  TRY_CAST(NULLIF(TRIM(ht_distrib_started), '') AS DATE) AS dt_ht_distrib_started,
  TRY_CAST(NULLIF(TRIM(ht_distrib_ended), '') AS DATE) AS dt_ht_distrib_ended,
  ts_load
FROM
  datalake_gsheets_raw.ind_agents_partner_allocation
