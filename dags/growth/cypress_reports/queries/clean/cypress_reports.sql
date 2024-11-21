SELECT
    id_test_execution,
    meta,
    results,
    stats,
    pwa,
    dt AS dt_created
FROM
    datalake_cypress_reports_raw.cypress_reports