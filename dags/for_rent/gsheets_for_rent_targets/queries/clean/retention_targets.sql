SELECT
    metric AS metric_name,
    granularity,
    CAST(REPLACE(target, ',', '.') AS DOUBLE) AS target,
    TO_DATE(time_ref, 'd/M/yyyy') AS dt_target_reference
FROM
    datalake_gsheets_raw.retention_targets