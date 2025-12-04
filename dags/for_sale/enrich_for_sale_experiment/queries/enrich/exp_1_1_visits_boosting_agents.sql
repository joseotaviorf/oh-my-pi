SELECT
    id_visitor AS identifier,
    1 AS id_neotribe,
    1 AS id_experiment,
    'VISITS XP' AS name_neotribe,
    'visits_boosting_agents' as name_experiment,
    'VISITOR' as identifier_type,
    business_context,
    CASE
        WHEN RIGHT(id_visitor, 2) >= 50 AND RIGHT(id_visitor, 2) <= 99 THEN 'CONTROL'
        WHEN RIGHT(id_visitor, 2) >= 00 AND RIGHT(id_visitor, 2) <= 49 THEN 'TREATMENT'
        ELSE 'ERROR'
    END AS test_group,
    CAST(NULL AS STRING) AS documentation_link,
    'Os BP são identificados de acordo com as visitas marcadas e divididos de acordo com o final do id' AS additional_information,
    DATE('2025-06-26') AS dt_started,
    DATE('2025-07-13') AS dt_ended,
    MIN(ts_created::DATE) AS dt_identifier_started
FROM
    datalake_ebdb_clean.visit
WHERE
    ts_created::DATE >= '2025-06-26'
    AND business_context = 'RENT'
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
