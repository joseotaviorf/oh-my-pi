SELECT
    id_broker AS sk_broker,
    broker_comercial_name,
    broker_name,
    street,
    `number`,
    complement,
    neighborhood,
    city,
    state,
    country_code,
    zipcode,
    creci,
    cnpj,
    is_broker_active,
    is_legacy,
    ts_created,
    NOW() AS ts_load
FROM
    datalake_velo.broker
