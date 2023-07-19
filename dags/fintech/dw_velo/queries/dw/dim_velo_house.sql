SELECT
    id_house As sk_house,
    `type`,
    street,
    `number`,
    complement,
    neighborhood,
    city,
    state,
    country_code,
    zipcode,
    is_legacy,
    NOW() AS ts_load
FROM
    datalake_velo.house
