SELECT DISTINCT
  DENSE_RANK() OVER (ORDER BY answer) AS sk_language,
  answer AS candidate_language
FROM 
  datalake_workable_redshift_clean.answers
WHERE 
  question LIKE '%Fala algum idioma estrangeiro?%'