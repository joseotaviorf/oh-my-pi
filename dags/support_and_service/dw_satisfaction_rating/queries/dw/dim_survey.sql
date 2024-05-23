WITH survey_first_seen AS (
  SELECT
      id_survey,
      MIN(sa.ts_submitted) AS ts_first_submitted
  FROM
      datalake_satisfaction_rating.satisfaction_answers AS sa
  GROUP BY 1
)
SELECT DISTINCT
    sa.id_survey AS sk_survey,
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
JOIN
    survey_first_seen AS sfs
      ON sfs.id_survey = sa.id_survey
WHERE
    DATE(sfs.ts_first_submitted) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
