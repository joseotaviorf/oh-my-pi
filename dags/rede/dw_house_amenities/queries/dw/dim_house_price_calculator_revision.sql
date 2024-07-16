WITH price_calculator_revision AS (
  SELECT
    r.id_house,
    r.p_70 AS price_p_70,
    ure.ts_revision,
    DATE_TRUNC('DAY', FROM_UNIXTIME(ure.ts_revision / 1000)) AS ts_started,
    ROW_NUMBER() OVER(PARTITION BY r.id_house, DATE_TRUNC('DAY', FROM_UNIXTIME(ure.ts_revision / 1000)) ORDER BY ure.ts_revision DESC) AS rn
  FROM
    datalake_ebdb_clean.house_predicted_price_aud AS r
  LEFT JOIN
    datalake_ebdb_clean.user_revision_entity AS ure 
    ON ure.id = r.rev
  LEFT JOIN
    datalake_ebdb_clean.house_aud AS ha
    ON ha.rev = r.rev
  WHERE
    r.business_context = 'SALE'
)
SELECT
  CONCAT(pc.id_house, pc.price_p_70) AS sk_price_calculator_revision,
  pc.id_house,
  pc.price_p_70,
  DATE(pc.ts_started) AS dt_revision_started,
  DATE_ADD(COALESCE(LEAD(pc.ts_started) OVER (PARTITION BY pc.id_house ORDER BY pc.ts_started), CURRENT_DATE), -1) AS dt_revision_ended,
  FROM_UTC_TIMESTAMP(CURRENT_TIMESTAMP(), 'America/Sao_Paulo') AS ts_load
FROM 
  price_calculator_revision AS pc
WHERE
  pc.rn = 1