SELECT
  id,
  externaldomainid AS id_external_domain,
  externaldomain AS external_domain,
  source_url,
  reason,
  created_at AS ts_created,
  year,
  month,
  day
FROM
  datalake_kodak_raw.photo_invalid_source
