SELECT
    id_region AS sk_region,
    COALESCE(CAST(DATE_FORMAT(DATE(ts_start_coverage), 'yyyyMMdd') AS BIGINT), -1) AS sk_coverage_started_date,
    COALESCE(CAST(DATE_FORMAT(DATE(ts_end_coverage), 'yyyyMMdd') AS BIGINT), -1) AS sk_coverage_ended_date,
    business_model,
    hub_name AS business_unit,
    DATE(ts_start_coverage) AS dt_coverage_started,
    DATE(ts_end_coverage) AS dt_coverage_ended,
    NOW() AS ts_load
FROM
    datalake_sale_visit_hubs.business_unit_region_history
