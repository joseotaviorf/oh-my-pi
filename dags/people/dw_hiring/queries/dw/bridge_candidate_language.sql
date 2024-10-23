SELECT
  MD5(CAST(c.id AS BINARY)) AS sk_candidate,
  COALESCE(dl.sk_language, '-1')  AS sk_language
FROM 
  datalake_workable_redshift_clean.candidates AS c
LEFT JOIN 
  datalake_workable_redshift_clean.answers AS a
    ON c.id = a.id_candidate
    AND a.question LIKE '%Fala algum idioma estrangeiro?%'
LEFT JOIN 
  dw_hiring.dim_language AS dl
    ON a.answer = dl.candidate_language