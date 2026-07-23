SELECT
  CONCAT_WS('_', v.id, v.business_context) AS identifier_bc,
  v.id AS identifier,
  1 AS id_neotribe,
  15 AS id_experiment,
  'VISITS XP' AS name_neotribe,
  'visits_reconfirmation_hsm_rent' AS name_experiment,
  'VISIT' AS identifier_type,
  v.business_context,
  IF((
    (
      v.id * 31 + 4 * 17
    ) % 100
  ) < 50, 'CONTROL', 'TREATMENT') AS test_group,
  CAST(NULL AS STRING) AS documentation_link,
  'Alocação aleatória baseada no ID da visita.' AS additional_information,
  MIN(CAST(v.ts_created AS DATE)) AS dt_identifier_started,
  MAX(CAST(v.ts_created AS DATE)) AS dt_identifier_ended
FROM datalake_ebdb_clean.visit AS v
WHERE
  CAST(v.ts_created AS DATE) >= CAST('2026-03-10' AS DATE)
  AND v.business_context = 'RENT' /* Experiment start */
  AND (
    (
      CAST(v.ts_created AS DATE) <= CAST('2026-04-12' AS DATE)
      AND business_context = 'RENT'
    )
  ) /* Experiment end */
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
