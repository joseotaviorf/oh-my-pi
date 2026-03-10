SELECT
    CONCAT_WS('_', id_visitor, business_context) AS identifier_bc,
    id_visitor AS identifier,
    1 AS id_neotribe,
    12 AS id_experiment,
    'VISITS XP' AS name_neotribe,
    'visits_boosting_agents_area_increased_to_800m' as name_experiment,
    'VISITOR' as identifier_type,
    business_context,
    IF(((id_visitor * 31 + 3 * 17) % 100) < 50, 'CONTROL', 'TREATMENT') AS test_group,
    CAST(NULL AS STRING) AS documentation_link,
    'Os TP/BP são identificados de acordo com as visitas marcadas e divididos de acordo com o seu identificador' AS additional_information,
    MIN(ts_created::DATE) AS dt_identifier_started,
    MAX(ts_created::DATE) AS dt_identifier_ended
FROM
    datalake_ebdb_clean.visit
WHERE
    ts_created::DATE >= '2026-01-06'
     AND (
        (ts_created::DATE >= '2026-01-06' AND business_context = 'RENT')
        OR
        (ts_created::DATE <= '2026-03-02' AND business_context = 'SALE')
    )
GROUP BY 1,2,3,4,5,6,7,8,9,10,11
