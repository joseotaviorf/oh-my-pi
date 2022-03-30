SELECT
    city_group,
    acquisition_channel,
    first_touchpoint,
    CAST(ca2cs AS DECIMAL(12,4)) AS ca2cs,
    CAST(cs AS DECIMAL(12,4)) AS cs,
    CAST(oa2ca AS DECIMAL(12,4)) AS oa2ca,
    CAST(os2oa AS DECIMAL(12,4)) AS os2oa,
    CAST(vb2vc AS DECIMAL(12,4)) AS vb2vc,
    CAST(vc2os AS DECIMAL(12,4)) AS vc2os,
    week_origin,
    TO_DATE(week_start, 'MM/dd/yyyy') AS dt_started_week
FROM
    datalake_gsheets_raw.forecast_cohort_demanda