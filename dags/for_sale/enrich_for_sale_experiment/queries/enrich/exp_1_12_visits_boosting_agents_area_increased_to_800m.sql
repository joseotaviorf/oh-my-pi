SELECT
  CONCAT_WS('_', id_visitor, business_context) AS identifier_bc,
  id_visitor AS identifier,
  1 AS id_neotribe,
  12 AS id_experiment,
  'VISITS XP' AS name_neotribe,
  'visits_boosting_agents_area_increased_to_800m' AS name_experiment,
  'VISITOR' AS identifier_type,
  business_context,
  IF((
    (
      id_visitor * 31 + 3 * 17
    ) % 100
  ) < 50, 'CONTROL', 'TREATMENT') AS test_group,
  CAST(NULL AS STRING) AS documentation_link,
  'Os TP/BP são identificados de acordo com as visitas marcadas e divididos de acordo com o seu identificador' AS additional_information,
  MIN(CAST(ts_created AS DATE)) AS dt_identifier_started,
  MAX(CAST(ts_created AS DATE)) AS dt_identifier_ended
FROM datalake_ebdb_clean.visit
WHERE
  CAST(ts_created AS DATE) >= '2026-01-06'
  AND (
    (
      CAST(ts_created AS DATE) >= '2026-01-06' AND business_context = 'RENT'
    )
    OR (
      CAST(ts_created AS DATE) <= '2026-03-02' AND business_context = 'SALE'
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
