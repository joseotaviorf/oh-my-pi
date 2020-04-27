SELECT
    id,
    updated_on as ts_updated,
    created_on as ts_created,
    house_id as id_house,
    enabled as is_enabled
FROM
    datalake_ebdb_raw.instantoffer