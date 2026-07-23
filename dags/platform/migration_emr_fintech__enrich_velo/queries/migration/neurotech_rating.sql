WITH neurotech_aux AS (
  SELECT
    id_propose,
    rating,
    ts_operation
  FROM (
    SELECT
      proposal_number AS id_propose,
      proposal_rating AS rating,
      ts_operation,
      ROW_NUMBER() OVER (PARTITION BY proposal_number ORDER BY ts_operation DESC) AS _w,
      proposal_number
    FROM datalake_velo_neurotech_clean.logs_credit_granting
    WHERE
      NOT proposal_number IS NULL
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  id_propose,
  CASE
    WHEN rating IS NULL
    THEN 'missing'
    WHEN rating = 'NaN'
    THEN 'missing'
    ELSE rating
  END AS rating,
  ts_operation
FROM neurotech_aux
