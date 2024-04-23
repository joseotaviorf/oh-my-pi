SELECT
    id,
    updated_on AS ts_updated,
    created_on AS ts_created,
    house_id AS id_house,
    enabled AS is_enabled
FROM
    datalake_ebdb_raw.instantoffer