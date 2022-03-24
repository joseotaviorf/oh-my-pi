SELECT
    FLOAT(rate) AS commission_rate,
    DATE(date_from) AS dt_from,
    DATE(date_until) AS dt_until
FROM
    datalake_gsheets_raw.tradecom_configuration
