SELECT
    metrica AS metric_name,
    time AS team,
    granularidade AS granularity,
    CAST(target AS double) AS target,
    DATE(inicio_vigencia) AS dt_start,
    DATE(fim_vigencia) AS dt_end
FROM
    datalake_gsheets_raw.target_support_kpis