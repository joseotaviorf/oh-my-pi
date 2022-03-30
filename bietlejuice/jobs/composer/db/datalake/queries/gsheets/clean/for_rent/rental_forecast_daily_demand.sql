SELECT
    city_group,
    acquisition_channel,
    first_touchpoint,
    CAST(ca AS DECIMAL(12,4)) AS ca,
    CAST(cs AS DECIMAL(12,4)) AS cs,
    CAST(oa AS DECIMAL(12,4)) AS oa,
    CAST(os AS DECIMAL(12,4)) AS os,
    CAST(vb AS DECIMAL(12,4)) AS vb,
    CAST(vc AS DECIMAL(12,4)) AS vc,
    TO_DATE(date, 'M/dd/yyyy') AS dt_created,
    TO_DATE(week_start, 'M/dd/yyyy') AS dt_started_week,
    CAST(year AS INT) AS year,
    CAST(halfyear AS INT) AS semester,
    CAST(quarter AS INT) AS quarter,
    CAST(month AS INT) AS month 
FROM
    datalake_gsheets_raw.forecast_diario_demanda