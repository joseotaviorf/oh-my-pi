WITH related AS (
  SELECT
    id_house,
    DATE(ts_created) AS dt_created
  FROM
    datalake_ebdb_clean.house_listing_relation
  WHERE
    DATE(ts_created) BETWEEN DATE('{load_start_date}') - INTERVAL 30 DAY AND DATE('{load_end_date}')
    AND source_type = 'COMPANY_REF'
    AND related_as = 'AUTONOMOUS_AGENT'
),
existing_houses AS (
  SELECT
    CAST(get_json_object(hs.details, '$.houseExternalId') AS BIGINT) AS id_house
  FROM
    datalake_big_agent.agency AS a
  LEFT JOIN 
    datalake_big_agent.house AS hs
      ON a.id_house = hs.id
),
all_houses_big_agent AS (
  SELECT
    CAST(get_json_object(details, '$.houseExternalId') AS BIGINT) AS id_house
  FROM
    datalake_big_agent.house
),
not_synchronized_houses AS (
  SELECT
    COUNT(r.id_house) AS quantity_of_houses,
    COLLECT_LIST(r.id_house) AS id_house,
    r.dt_created
  FROM
    related AS r
  LEFT JOIN 
    existing_houses AS eh
      ON r.id_house = eh.id_house
  JOIN 
    all_houses_big_agent AS hb
      ON r.id_house = hb.id_house
  WHERE
    eh.id_house IS NULL
  GROUP BY
    r.dt_created
)
SELECT
  *
FROM
  not_synchronized_houses
UNION ALL
SELECT
  0 AS quantity_of_houses,
  ARRAY() AS id_house,
  CURRENT_DATE AS dt_created
WHERE 
  NOT EXISTS (SELECT 1 FROM not_synchronized_houses)