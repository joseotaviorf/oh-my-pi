SELECT
  id,
  externaldomainid AS id_external_domain,
  externaldomain AS external_domain,
  metadata,
  path,
  rev,
  revtype AS rev_type,
  revend AS rev_end,
  metadata_mod AS mod_metadata,
  path_mod AS mod_path
FROM
  datalake_kodak_raw.photo_aud
