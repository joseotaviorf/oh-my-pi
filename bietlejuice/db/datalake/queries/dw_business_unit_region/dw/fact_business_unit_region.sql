SELECT 
    id_region AS sk_region,
    COALESCE(CAST(DATE_FORMAT(dt_start, 'yyyyMMdd') AS BIGINT), -1) AS sk_coverage_started_date,
    COALESCE(CAST(DATE_FORMAT(dt_end, 'yyyyMMdd') AS BIGINT), -1) AS sk_coverage_ended_date,
    business_model,
    business_unit,
    dt_start AS dt_coverage_started,
    dt_end AS dt_coverage_ended,
    NOW() AS ts_load
FROM 
    datalake_gsheets_clean.business_unit_region