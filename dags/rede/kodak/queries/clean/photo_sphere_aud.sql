SELECT
  id,
  rev,
  revtype AS rev_type,
  revend AS rev_end,
  externaldomain AS external_domain,
  externaldomainid AS id_external_domain,
  metadata,
  metadata_mod AS mod_metadata,
  path,
  path_mod AS mod_path,
  pathpreview AS path_preview,
  pathpreview_mod AS mod_path_preview,
  position,
  position_mod AS mod_position
FROM
  datalake_kodak_raw.photosphere_aud
