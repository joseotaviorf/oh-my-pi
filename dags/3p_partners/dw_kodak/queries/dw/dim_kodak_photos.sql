SELECT
  p.id AS sk_kodak_photo,
  p.id_external_domain,
  p.external_domain,
  GET_JSON_OBJECT(p.metadata, '$.description') AS description,
  GET_JSON_OBJECT(p.metadata, '$.mimetype') AS mime_type,
  GET_JSON_OBJECT(p.metadata, '$.order') AS order,
  p.path,
  GET_JSON_OBJECT(p.metadata, '$.source_name') AS source_name,
  GET_JSON_OBJECT(p.metadata, '$.source_url') AS source_url,
  NOW() AS ts_load
FROM
  datalake_kodak_clean.photo AS p