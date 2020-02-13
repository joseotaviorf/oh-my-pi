SELECT
    id,
    timestamp(created_at) as ts_created,
    timestamp(updated_at) as ts_updated,
    version,
    cellphone as cell_phone,
    cpf,
    email,
    main_id as id_main,
    name
FROM
    datalake_kill_queue_raw.user