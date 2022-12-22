SELECT
    id,
    type AS id_type,
    status AS id_status,
    plan AS id_plan,
    step AS id_step,
    activator AS id_activator,
    externalref AS id_external,
    realtor AS id_realtor,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    hash,
    BOOLEAN(active) AS is_active,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated
FROM
    datalake_velo_raw.fiancavelo_propose
