SELECT
  id,
  externaldomain AS external_domain,
  externaldomainid AS id_external_domain,
  metadata,
  path,
  pathpreview AS path_preview,
  position
FROM
  datalake_kodak_raw.photosphere
