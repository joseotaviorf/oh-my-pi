SELECT
    id,
    propose AS id_propose,
    objecttype AS id_object_type,
    property AS id_property,
    description,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    BOOLEAN(active) AS is_active,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.fiancavelo_object_legacy
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY dateupdate DESC) = 1
