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
    active AS is_active,
    dateinsert AS ts_insert,
    dateupdate AS ts_update
FROM
    datalake_velo_raw.fiancavelo_colaborador
