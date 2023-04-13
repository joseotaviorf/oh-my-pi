SELECT
    id,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    propose AS id_propose,
    document AS id_document,
    active AS is_active,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.propose_documents

QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY dateupdate DESC) = 1
