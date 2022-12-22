SELECT
    id,
    person AS id_person,
    user AS id_user,
    type AS id_type,
    externalref AS id_external,
    realestate AS id_realestate,
    creci AS id_creci,
    walletId AS id_wallet,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    apiKey,
    BOOLEAN(active) AS is_active,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated
FROM
    datalake_velo_raw.fiancavelo_colaborador
