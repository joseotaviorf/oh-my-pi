SELECT
    id,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    propose AS id_propose,
    type AS id_property_type,
    address AS id_address,
    active AS is_active,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.property_propose
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
