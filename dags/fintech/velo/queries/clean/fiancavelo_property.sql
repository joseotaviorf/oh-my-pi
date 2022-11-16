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
    active AS is_active,
    dateinsert AS ts_insert,
    dateupdate AS ts_update
FROM
    datalake_velo_raw.fiancavelo_property
