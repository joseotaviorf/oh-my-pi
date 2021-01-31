SELECT
    id,
    EXPLODE(FROM_JSON(customers,'array<string>')) AS customers_explode,
    ts_created,
    DATE(CONCAT(CAST(year AS VARCHAR(4)), '-', CAST(month AS VARCHAR(2)), '-', CAST(day AS VARCHAR(2)))) AS dt_updated
FROM
    datalake_tracksale_clean.dispatch
