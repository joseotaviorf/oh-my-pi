WITH visit_tenant_living AS (
    SELECT
        CONCAT_WS('_', c.id_user, v.business_context) AS identifier_bc,
        v.id AS id_visit,
        c.id_user AS identifier,
        v.business_context,
        u.main_phone,
        v.ts_created AS ts_visit_created,
        ROW_NUMBER() OVER(PARTITION BY v.id ORDER BY c.dt_started DESC) AS rn
    FROM
        datalake_ebdb_clean.visit AS v
    JOIN
        datalake_ebdb_clean.contract AS c
            ON v.id_house = c.id_house
            AND c.status IN ('Ativo', 'Finalizado')
            AND DATE(v.ts_visit) >= c.dt_started
            AND DATE(v.ts_visit) < COALESCE(c.dt_termination, CURRENT_DATE)
    LEFT JOIN
        datalake_ebdb_clean.user AS u
            ON c.id_user = u.id
    WHERE
        DATE(v.ts_created) >= DATE('2026-06-29')
)
SELECT
    identifier_bc,
    identifier,
    1 AS id_neotribe,
    17 AS id_experiment,
    'VISITS XP' AS name_neotribe,
    'visits_triangulation_tenant_living' AS name_experiment,
    'TENANT_LIVING' AS identifier_type,
    business_context,
    CASE
      WHEN RIGHT(NULLIF(main_phone, ''), 1) IN (1,3,4,6,9) THEN 'CONTROL'
      WHEN RIGHT(NULLIF(main_phone, ''), 1) IN (0,2,5,7,8) THEN 'TREATMENT'
      ELSE 'ERROR'
    END AS test_group,
    CAST(NULL AS STRING) AS documentation_link,
    'O tenant living é identificado de acordo com o dígito final do seu telefone.' AS additional_information,
    MIN(DATE(ts_visit_created)) AS dt_identifier_started,
    MAX(DATE(ts_visit_created)) AS dt_identifier_ended
FROM
    visit_tenant_living
WHERE
    rn = 1
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
