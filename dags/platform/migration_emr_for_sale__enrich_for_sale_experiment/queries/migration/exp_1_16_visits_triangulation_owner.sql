SELECT
    CONCAT_WS('_', h.id_user, v.business_context) AS identifier_bc,
    h.id_user AS identifier,
    1 AS id_neotribe,
    16 AS id_experiment,
    'VISITS XP' AS name_neotribe,
    'visits_triangulation_owner' AS name_experiment,
    'OWNER' AS identifier_type,
    v.business_context,
    CASE
      WHEN RIGHT(NULLIF(u.main_phone, ''), 1) IN (1,3,4,6,9) THEN 'CONTROL'
      WHEN RIGHT(NULLIF(u.main_phone, ''), 1) IN (0,2,5,7,8) THEN 'TREATMENT'
      ELSE 'ERROR'
    END AS test_group,
    CAST(NULL AS STRING) AS documentation_link,
    'Os Owners são identificados de acordo com o dígito final do seu telefone.' AS additional_information,
    MIN(DATE(v.ts_created)) AS dt_identifier_started,
    MAX(DATE(v.ts_created)) AS dt_identifier_ended
FROM
    datalake_ebdb_clean.visit AS v
LEFT JOIN
    datalake_ebdb_clean.house AS h
        ON v.id_house = h.id
LEFT JOIN
    datalake_ebdb_clean.user AS u
        ON h.id_user = u.id
WHERE
    DATE(v.ts_created) >= DATE('2026-06-01')
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
