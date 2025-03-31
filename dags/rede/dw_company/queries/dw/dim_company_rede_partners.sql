SELECT
  cs.sk_company,
  cs.id_company,
  COALESCE(cm.id_company, -1) AS id_hubspot,
  COALESCE(cm.id_hubspot_owner, -1) AS id_account_manager,
  cs.uuid_company,
  cs.cnpj AS cnpj,
  COALESCE(a.city, 'Unknown') AS company_city,
  COALESCE(cm.company_cluster, 'Unknown') AS company_cluster,
  COALESCE(cm.company_cluster_performance, 'Unknown') AS company_performance_cluster,
  COALESCE(a.country, 'Unknown') AS company_country,
  COALESCE(ci.company_name, 'Unknown') AS company_integrator_partner,
  c.company_name,
  COALESCE(a.neighborhood, 'Unknown') AS company_neigborhood,
  COALESCE(a.state, 'Unknown') AS company_state,
  c.status AS company_status,
  c.trade_name AS company_trade_name,
  COALESCE(REGEXP_REPLACE(a.zip_code, '[^0-9]', ''), -1) AS company_zip_code,
  COALESCE(cm.extracted_3p_tag, 'Unknown') AS hubspot_company_name,
  COALESCE(cm.crm, 'Unknown') AS hubspot_crm,
  COALESCE(cm.member_category, 'Unknown') AS hubspot_member_category,
  cm.sale_lead_status AS hubspot_status,
  cm.is_flagged_as_leadgen AS is_flagged_as_leadgen_in_hubspot,
  MAX(CASE WHEN mu.hubspot_status = 'Membro' THEN mu.ts_start ELSE NULL END) AS ts_membership_start,
  MAX(CASE WHEN mu.hubspot_status = 'Membro' THEN mu.ts_end ELSE NULL END) AS ts_membership_end,
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
INNER JOIN
  datalake_hubspot.company_members AS cm
    ON cs.id_hubspot = cm.id_company
LEFT JOIN
  datalake_hubspot.membership_updates AS mu
    ON cm.id_company = mu.id_hubspot
LEFT JOIN
  datalake_company_clean.company AS ci
    ON cs.uuid_integrator_partner = ci.uuid_company
GROUP BY
  ALL