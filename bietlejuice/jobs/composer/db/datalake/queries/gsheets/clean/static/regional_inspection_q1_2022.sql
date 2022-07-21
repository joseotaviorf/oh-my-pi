SELECT
    CAST(id AS BIGINT) AS id,
    neighbourhood,
    regional_inspection_q1_2022,
    regional_inspection_q2_2022
FROM
    datalake_gsheets_raw.regional_inspection_q1_2022
    