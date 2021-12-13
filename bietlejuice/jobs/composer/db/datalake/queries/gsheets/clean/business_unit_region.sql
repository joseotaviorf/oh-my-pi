SELECT
    CAST(id_region AS BIGINT) AS id_region,
    business_model,
    business_unit,
    CAST(start_date AS DATE) AS dt_start,
    CAST(end_date AS DATE) AS dt_end
FROM
    datalake_gsheets_raw.business_unit_region
