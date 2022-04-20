SELECT
    CAST(id AS BIGINT) AS id,
    neighbourhood,
    regional_inspection
FROM
    datalake_gsheets_raw.regional_inspection_q1_2022