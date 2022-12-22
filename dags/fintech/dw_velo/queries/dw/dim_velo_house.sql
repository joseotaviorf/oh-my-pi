SELECT
    id_house As sk_house,
    `type`,
    city,
    state,
    country,
    zipcode,
    geolocation,
    NOW() AS ts_load
FROM
    datalake_velo.house
