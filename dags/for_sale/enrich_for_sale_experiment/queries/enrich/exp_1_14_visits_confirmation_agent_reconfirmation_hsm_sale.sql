SELECT
    CONCAT_WS('_', v.id_visitor, v.business_context) AS identifier_bc,
    v.id_visitor AS identifier,
    1 AS id_neotribe,
    14 AS id_experiment,
    'VISITS XP' AS name_neotribe,
    'visits_confirmation_agent_reconfirmation_hsm_sale' as name_experiment,
    'VISITOR' as identifier_type,
    v.business_context,
    CASE
      WHEN RIGHT(NULLIF(u.main_phone, ''), 3) >= 500 THEN 'CONTROL'
      WHEN RIGHT(NULLIF(u.main_phone, ''), 3) <= 499 THEN 'TREATMENT'
      ELSE 'ERROR'
    END AS test_group,
    CAST(NULL AS STRING) AS documentation_link,
    'Os BP são identificados de acordo com o final do seu telefone.' AS additional_information,
    MIN(v.ts_created::DATE) AS dt_identifier_started,
    MAX(v.ts_created::DATE) AS dt_identifier_ended
FROM
    datalake_ebdb_clean.visit AS v
LEFT JOIN
    datalake_ebdb_clean.user AS u
        ON v.id_visitor = u.id
WHERE
    DATE(v.ts_created) >= DATE('2026-03-10') AND v.business_context='SALE' --Experiment start
    AND ( --Rollout expansions
     (RIGHT(NULLIF(u.main_phone, ''), 3) >= 800 OR RIGHT(NULLIF(u.main_phone, ''), 3) <= 199)
    )
    AND ( --Experiment end
    (v.ts_created::DATE >= DATE('2026-03-10') AND business_context = 'SALE'))
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
