SELECT
  CONCAT_WS('_', id_visitor, business_context) AS identifier_bc,
  id_visitor AS identifier,
  1 AS id_neotribe,
  1 AS id_experiment,
  'VISITS XP' AS name_neotribe,
  'visits_boosting_agents' AS name_experiment,
  'VISITOR' AS identifier_type,
  business_context,
  CASE
    WHEN RIGHT(id_visitor, 2) >= 50 AND RIGHT(id_visitor, 2) <= 99
    THEN 'CONTROL'
    WHEN RIGHT(id_visitor, 2) >= 00 AND RIGHT(id_visitor, 2) <= 49
    THEN 'TREATMENT'
    ELSE 'ERROR'
  END AS test_group,
  CAST(NULL AS STRING) AS documentation_link,
  'Os TP/BP são identificados de acordo com as visitas marcadas e divididos de acordo com o final do id' AS additional_information,
  MIN(CAST(ts_created AS DATE)) AS dt_identifier_started,
  MAX(CAST(ts_created AS DATE)) AS dt_identifier_ended
FROM datalake_ebdb_clean.visit
WHERE
  CAST(ts_created AS DATE) >= '2025-06-26'
  AND (
    (
      CAST(ts_created AS DATE) <= '2025-07-13' AND business_context = 'RENT'
    )
    OR (
      CAST(ts_created AS DATE) <= '2025-08-19' AND business_context = 'SALE'
    )
  )
GROUP BY
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11
