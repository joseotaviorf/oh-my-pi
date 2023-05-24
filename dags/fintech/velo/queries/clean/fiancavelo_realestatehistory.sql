SELECT
    id,
    userinsert  AS id_user_insert,
    userupdate  AS id_user_update,
    realstate   AS id_real_state,
    description,
    field,
    oldvalue    AS old_value,
    newvalue    AS new_value,
    active,
    dateinsert  AS ts_inserted,
    dateupdate  AS ts_updated
FROM
    datalake_velo_raw.fiancavelo_realestatehistory
