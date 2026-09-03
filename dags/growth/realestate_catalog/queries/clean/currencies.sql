SELECT
    idmoneda AS id_currency,
    codigomoneda AS currency_code,
    simbolo AS currency_symbol,
    nombre AS currency_name
FROM
    datalake_realestate_raw.monedas
