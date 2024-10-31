SELECT
    moeda AS currency,
    FLOAT(cotacao) AS cotation,
    ts_load
FROM datalake_gsheets_people_raw.currency_quote_people