SELECT
    id,
    userupdate AS id_user_update,
    name,
    hash,
    BOOLEAN(active) AS is_active,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated
FROM
    datalake_velo_raw.velosign_template
