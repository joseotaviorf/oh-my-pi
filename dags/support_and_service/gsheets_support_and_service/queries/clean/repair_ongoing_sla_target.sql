SELECT
    metrica AS metric_name,
    time AS squad,
    granularidade AS granularity,
    tag_1,
    tag_2,
    tag_3,
    tag_4,
    tag_5,
    tag_6,
    tag_7,
    tag_8,
    tag_9,
    CAST(target AS FLOAT) AS target,
    DATE(inicio_vigencia) AS dt_started,
    DATE(fim_vigencia) AS dt_finished,
    TIMESTAMP(ts_load) AS ts_load
FROM
    datalake_gsheets_raw.repair_ongoing_sla_target