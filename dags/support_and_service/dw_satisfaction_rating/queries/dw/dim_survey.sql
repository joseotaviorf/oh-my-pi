WITH survey_first_seen AS (
  SELECT 
    id_survey, 
    MIN(sa.ts_submitted) AS ts_first_submitted 
  FROM 
    datalake_satisfaction_rating.satisfaction_answers AS sa 
  GROUP BY 
    1
), 
previous_surveys AS (
  SELECT 
    DISTINCT sa.id_survey AS sk_survey, 
    sa.service_type, 
    sa.service_context, 
    sa.source_name, 
    sa.survey_name, 
    sfs.ts_first_submitted, 
    NOW() AS ts_load, 
    YEAR(sfs.ts_first_submitted) AS year, 
    MONTH(sfs.ts_first_submitted) AS month, 
    DAY(sfs.ts_first_submitted) AS day 
  FROM 
    datalake_satisfaction_rating.satisfaction_answers AS sa 
    JOIN survey_first_seen AS sfs ON sfs.id_survey = sa.id_survey 
  WHERE 
    DATE(sfs.ts_first_submitted) BETWEEN DATE('{load_start_date}') 
    AND DATE('{load_end_date}')
), 
survicate_first_seen AS (
  SELECT 
    sss.id_survey, 
    MIN(sss.ts_submitted) AS ts_first_submitted 
  FROM 
    datalake_survicate.single_station_surveys AS sss 
  GROUP BY 
    1
), 
pet_surveys AS (
  SELECT 
    DISTINCT sss.id_survey AS sk_survey, 
    sss.service_type, 
    sss.service_context, 
    sss.source_name, 
    sss.survey_name, 
    svfs.ts_first_submitted, 
    NOW() AS ts_load, 
    YEAR(svfs.ts_first_submitted) AS year, 
    MONTH(svfs.ts_first_submitted) AS month, 
    DAY(svfs.ts_first_submitted) AS day 
  FROM 
    datalake_survicate.single_station_surveys AS sss 
    JOIN survicate_first_seen AS svfs ON svfs.id_survey = sss.id_survey 
  WHERE 
    DATE(svfs.ts_first_submitted) BETWEEN DATE('{load_start_date}') 
    AND DATE('{load_end_date}')
) 
SELECT 
  * 
FROM 
  previous_surveys 
UNION ALL 
SELECT 
  * 
FROM 
  pet_surveys
