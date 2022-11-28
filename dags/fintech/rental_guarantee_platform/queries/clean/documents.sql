SELECT
    id,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    type AS id_document_type,
    status AS id_document_status,
    `uuid`,
    name,
    link,
    lenght,
    data_type,
    description,
    active AS is_active,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.documents
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
