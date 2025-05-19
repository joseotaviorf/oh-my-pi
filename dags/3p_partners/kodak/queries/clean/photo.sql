SELECT
  id,
  externaldomainid AS id_external_domain,
  externaldomain AS external_domain,
  metadata,
  path
FROM
  datalake_kodak_raw.photo
