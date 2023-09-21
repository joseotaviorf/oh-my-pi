SELECT
    id,
    propose AS id_propose,
    person AS id_person,
    type AS id_type,
    BOOLEAN(active) AS is_active,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.fiancavelo_proposeperson_legacy
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY dateupdate DESC) = 1
