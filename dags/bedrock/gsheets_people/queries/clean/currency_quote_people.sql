SELECT
    FLOAT(euro) AS euro_cotation,
    FLOAT(dolar) AS dolar_cotation,
    FLOAT(mexico) AS mexican_peso_cotation,
    ts_load
FROM datalake_gsheets_raw.currency_quote_people