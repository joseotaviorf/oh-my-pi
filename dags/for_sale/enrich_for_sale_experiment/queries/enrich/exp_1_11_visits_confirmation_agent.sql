SELECT
  CONCAT_WS('_', v.id_visitor, v.business_context) AS identifier_bc,
  v.id_visitor AS identifier,
  1 AS id_neotribe,
  11 AS id_experiment,
  'VISITS XP' AS name_neotribe,
  'visits_confirmation_agent' AS name_experiment,
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
  'Os TP/BP são identificados de acordo com o final do seu telefone.' AS additional_information,
  MIN(CAST(v.ts_created AS DATE)) AS dt_identifier_started,
  MAX(CAST(v.ts_created AS DATE)) AS dt_identifier_ended
FROM datalake_ebdb_clean.visit AS v
LEFT JOIN datalake_ebdb_clean.user AS u
  ON v.id_visitor = u.id
WHERE
  CAST(v.ts_created AS DATE) >= CAST('2025-12-10' AS DATE) /* Experiment start */
  AND (
    (
      RIGHT(NULLIF(u.main_phone, ''), 3) >= 950
      OR RIGHT(NULLIF(u.main_phone, ''), 3) <= 049
    )
    OR (
      CAST(v.ts_created AS DATE) >= CAST('2026-01-19' AS DATE)
      AND v.business_context = 'RENT'
      AND (
        RIGHT(NULLIF(u.main_phone, ''), 3) >= 900
        OR RIGHT(NULLIF(u.main_phone, ''), 3) <= 099
      )
    )
    OR (
      CAST(v.ts_created AS DATE) >= CAST('2026-01-20' AS DATE)
      AND v.business_context = 'RENT'
      AND (
        RIGHT(NULLIF(u.main_phone, ''), 3) >= 850
        OR RIGHT(NULLIF(u.main_phone, ''), 3) <= 149
      )
    )
    OR (
      CAST(v.ts_created AS DATE) >= CAST('2026-01-21' AS DATE)
      AND v.business_context = 'RENT'
      AND (
        RIGHT(NULLIF(u.main_phone, ''), 3) >= 800
        OR RIGHT(NULLIF(u.main_phone, ''), 3) <= 199
      )
    )
    OR (
      CAST(v.ts_created AS DATE) >= CAST('2026-02-04' AS DATE)
      AND v.business_context = 'RENT'
      AND (
        RIGHT(NULLIF(u.main_phone, ''), 3) >= 500
        OR RIGHT(NULLIF(u.main_phone, ''), 3) <= 499
      )
    )
    OR (
      CAST(v.ts_created AS DATE) >= CAST('2026-03-10' AS DATE)
      AND v.business_context = 'SALE'
      AND (
        RIGHT(NULLIF(u.main_phone, ''), 3) >= 800
        OR RIGHT(NULLIF(u.main_phone, ''), 3) <= 199
      )
    )
  ) /* Rollout expansions */
  AND (
    (
      CAST(v.ts_created AS DATE) <= '2026-03-02' AND business_context = 'RENT'
    )
    OR (
      CAST(v.ts_created AS DATE) <= '2026-03-09' AND business_context = 'SALE'
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
