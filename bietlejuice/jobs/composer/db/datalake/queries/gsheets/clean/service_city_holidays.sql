SELECT
    CAST(id_city AS BIGINT) AS id_city,
    Categoria AS category,
    Cidade AS city,
    Feriado_Nome AS description,
    Regional AS regional,
    Estado AS state,
    TO_DATE(Data) AS dt_holiday
FROM
    datalake_gsheets_raw.service_city_holidays