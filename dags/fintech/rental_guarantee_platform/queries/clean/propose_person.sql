SELECT
    id,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    propose AS id_propose,
    type AS id_propose_person_type,
    person AS uuid_person,
    address,
    name,
    declared_income,
    is_foreign,
    `sign` AS has_sign,
    active AS is_active,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated
FROM
    datalake_rental_guarantee_platform_raw.propose_person
