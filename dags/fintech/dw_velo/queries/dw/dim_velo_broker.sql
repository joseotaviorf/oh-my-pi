SELECT
    id_broker AS sk_broker,
    broker_name,
    city,
    state,
    country,
    zipcode,
    geolocation,
    creci,
    cnpj,
    is_broker_active,
    NOW() AS ts_load
FROM
    datalake_velo.broker
