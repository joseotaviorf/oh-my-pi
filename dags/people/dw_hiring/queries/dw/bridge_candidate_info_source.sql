SELECT 
  MD5(CAST(c.id AS BINARY)) AS sk_candidate,
  COALESCE(info_source.sk_info_source, '-1') AS sk_info_source
FROM 
  datalake_workable_redshift_clean.candidates AS c
LEFT JOIN 
  datalake_workable.info_source
    ON c.id = info_source.id_candidate