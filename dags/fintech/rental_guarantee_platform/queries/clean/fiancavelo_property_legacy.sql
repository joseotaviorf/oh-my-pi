SELECT
    id,
    propertytype AS id_property_type,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    neighborhood,
    street,
    number,
    complement,
    zipcode,
    city,
    state,
    country,
    geolocation,
    BOOLEAN(active) AS is_active,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.fiancavelo_property_legacy
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY dateupdate DESC) = 1
