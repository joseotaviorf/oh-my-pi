SELECT
  CONCAT_WS('_', v.id_visitor, v.business_context) AS identifier_bc,
  v.id_visitor AS identifier,
  1 AS id_neotribe,
  14 AS id_experiment,
  'VISITS XP' AS name_neotribe,
  'visits_confirmation_agent_reconfirmation_hsm_sale' AS name_experiment,
  'VISITOR' AS identifier_type,
  v.business_context,
  CASE
    WHEN RIGHT(NULLIF(u.main_phone, ''), 3) >= 500
    THEN 'CONTROL'
    WHEN RIGHT(NULLIF(u.main_phone, ''), 3) <= 499
    THEN 'TREATMENT'
    ELSE 'ERROR'
  END AS test_group,
  CAST(NULL AS STRING) AS documentation_link,
  'Os BP são identificados de acordo com o final do seu telefone.' AS additional_information,
  MIN(CAST(v.ts_created AS DATE)) AS dt_identifier_started,
  MAX(CAST(v.ts_created AS DATE)) AS dt_identifier_ended
FROM datalake_ebdb_clean.visit AS v
LEFT JOIN datalake_ebdb_clean.user AS u
  ON v.id_visitor = u.id
WHERE
  CAST(v.ts_created AS DATE) >= CAST('2026-03-20' AS DATE)
  AND v.business_context = 'SALE' /* Experiment start */
  AND (
    (
      RIGHT(NULLIF(u.main_phone, ''), 3) >= 800
      OR RIGHT(NULLIF(u.main_phone, ''), 3) <= 199
    )
    OR (
      CAST(v.ts_created AS DATE) >= CAST('2026-03-31' AS DATE)
      AND (
        RIGHT(NULLIF(u.main_phone, ''), 3) >= 650
        OR RIGHT(NULLIF(u.main_phone, ''), 3) <= 349
      )
    )
    OR (
      CAST(v.ts_created AS DATE) >= CAST('2026-04-13' AS DATE)
      AND (
        RIGHT(NULLIF(u.main_phone, ''), 3) >= 500
        OR RIGHT(NULLIF(u.main_phone, ''), 3) <= 499
      )
    )
  ) /* Rollout expansions */
  AND (
    (
      CAST(v.ts_created AS DATE) < CAST('2026-05-19' AS DATE)
      AND business_context = 'SALE'
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
