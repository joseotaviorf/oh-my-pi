SELECT
    metrica AS metric_name,
    time AS team,
    granularidade AS granularity,
    CAST(target AS DOUBLE) AS target,
    DATE(inicio_vigencia) AS dt_start,
    DATE(fim_vigencia) AS dt_end
FROM
    datalake_gsheets_raw.target_service_kpis