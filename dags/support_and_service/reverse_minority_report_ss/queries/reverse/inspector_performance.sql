SELECT
    id_inspector,
    inspections_conversion,
    eligible_inspections
FROM
    datalake_inspections_metrics.inspector_performance
WHERE
    dt_load = DATE('{year}-{month}-{day}')
