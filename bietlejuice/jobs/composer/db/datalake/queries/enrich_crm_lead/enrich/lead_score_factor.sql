WITH t_dates AS (
  SELECT
      CAST(id_origin AS BIGINT) AS id_lead,
      CAST(score_factor AS BIGINT) AS score_factor,
      ROW_NUMBER() OVER (PARTITION BY CAST(id_origin AS BIGINT) ORDER BY year, month, day, ts_start) AS rn
  FROM datalake_crm.tasks
  WHERE origin = 'Lead'
)
SELECT
  id_lead,
  score_factor
FROM t_dates
WHERE rn = 1