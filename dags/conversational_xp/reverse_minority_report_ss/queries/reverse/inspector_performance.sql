SELECT
    id_inspector,
    inspections_conversion,
    eligible_inspections
FROM
    datalake_inspections_metrics.inspector_performance
WHERE
    dt_load = DATE('{year}-{month}-{day}') - INTERVAL 1 DAY -- dt_load is actually D-2
