SELECT
    id,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    person AS id_propose_person,
    propose AS id_propose,
    document AS id_document,
    active AS is_active,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.person_documents
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
