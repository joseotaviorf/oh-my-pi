SELECT
  id,
  externaldomainid AS id_external_domain,
  externaldomain AS external_domain,
  metadata,
  path,
  ai_enhanced AS is_ai_enhanced,
  year,
  month,
  day
FROM
  datalake_kodak_raw.photo
