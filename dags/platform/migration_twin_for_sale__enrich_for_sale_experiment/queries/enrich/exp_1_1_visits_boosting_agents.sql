SELECT
    CONCAT_WS('_', id_visitor, business_context) AS identifier_bc,
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
    'Os TP/BP são identificados de acordo com as visitas marcadas e divididos de acordo com o final do id' AS additional_information,
    MIN(ts_created::DATE) AS dt_identifier_started,
    MAX(ts_created::DATE) AS dt_identifier_ended
FROM
    datalake_ebdb_clean.visit
WHERE
    ts_created::DATE >= '2025-06-26'
    AND (
        (ts_created::DATE <= '2025-07-13' AND business_context = 'RENT')
        OR
        (ts_created::DATE <= '2025-08-19' AND business_context = 'SALE')
    )
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
