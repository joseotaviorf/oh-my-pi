SELECT
    idpais AS id_country,
    idtraduccion AS id_translation,
    idmonedalocal AS id_local_currency,
    nombre AS country_name,
    codigo AS country_code,
    moneda AS currency_code,
    mediadepostulacion AS application_medium,
    estamos AS is_active_market
FROM
    datalake_realestate_raw.paises
