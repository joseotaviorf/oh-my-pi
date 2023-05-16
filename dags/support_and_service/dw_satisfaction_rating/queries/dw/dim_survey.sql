WITH survey_first_seen AS (
  SELECT
    id_survey,
    MIN(COALESCE(sa.ts_first_seen, sa.ts_submitted)) FILTER (WHERE COALESCE(sa.ts_first_seen, sa.ts_submitted) IS NOT NULL) AS ts_first_seen
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
    sfs.ts_first_seen,
    NOW() AS ts_load,
    YEAR(sfs.ts_first_seen) AS year,
    MONTH(sfs.ts_first_seen) AS month,
    DAY(sfs.ts_first_seen) AS day
FROM
    datalake_satisfaction_rating.satisfaction_answers AS sa
JOIN
    survey_first_seen AS sfs
      ON sfs.id_survey = sa.id_survey
WHERE
    DATE(sfs.ts_first_seen) = DATE('{year}-{month}-{day}')