SELECT
    code AS currency_from,
    codein AS currency_to,
    currency_pair,
    CAST(high AS DECIMAL(18,6)) AS high_rate,
    CAST(low AS DECIMAL(18,6)) AS low_rate,
    CAST(varBid AS DECIMAL(18,6)) AS bid_variation,
    CAST(pctChange AS DECIMAL(18,6)) AS percent_change,
    CAST(bid AS DECIMAL(18,6)) AS bid_price,
    CAST(ask AS DECIMAL(18,6)) AS ask_price,
    DATE(create_date) AS dt_created,
    FROM_UNIXTIME(CAST(timestamp AS BIGINT)) AS ts_recorded_at,
    TIMESTAMP(create_date) AS ts_created,
    NOW() AS ts_load
FROM
    datalake_awesomeapi_currency_rates_raw.currency_closing_rates
WHERE
    DATE(create_date) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
