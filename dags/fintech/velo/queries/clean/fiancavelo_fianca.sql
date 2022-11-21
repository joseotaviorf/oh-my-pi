SELECT
    id,
    realtor AS id_realtor,
    realestate AS id_realestate,
    responsible AS id_responsible,
    type AS id_type,
    status AS id_status,
    externalref AS id_external,
    propose AS id_propose,
    validity AS id_validity,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    BOOLEAN(active) AS is_active,
    begin AS dt_begin,
    end AS dt_end,
    dateinsert AS ts_insert,
    dateupdate AS ts_update
FROM
    datalake_velo_raw.fiancavelo_fianca
