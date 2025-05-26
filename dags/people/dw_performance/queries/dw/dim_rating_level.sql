SELECT
  rlb.id_rating_level AS sk_rating_level,
  rmb.rating_model_code,
  CASE rmt.rating_model_name
    WHEN 'Risk of Loss Rating Model' THEN 'Risk of Loss'
    WHEN 'Modelo de Classificação Criticidade' THEN 'Criticality'
    WHEN 'Modelo de Classificação de Prontidão' THEN 'Readiness'
    WHEN 'Potential Rating Model' THEN 'Potential'
    ELSE rmt.rating_model_name
  END AS rating_model_name,   
  rlt.rating_description, 
  rlt.review_rating_description,
  rlb.numeric_rating,
  rlt.ts_created,
  rlt.ts_updated,
  NOW() AS ts_load
FROM 
  datalake_pin_talent_clean.rating_level_base AS rlb
INNER JOIN
  datalake_pin_talent_clean.rating_level_translation AS rlt 
    ON rlb.id_rating_level = rlt.id_rating_level
INNER JOIN 
  datalake_pin_talent_clean.rating_model_base AS rmb
    ON rlb.id_rating_model = rmb.id_rating_model
INNER JOIN 
  datalake_pin_talent_clean.rating_model_translation AS rmt
    ON rlb.id_rating_model = rmt.id_rating_model
WHERE 
  rlt.language = 'US'
  AND rmt.language = 'US'
  AND rmt.rating_model_name IN (
    'Risk of Loss Rating Model',
    'Modelo de Classificação Criticidade',
    'Modelo de Classificação de Prontidão',
    'Potential Rating Model'
  )
 