SELECT
    id,
    main_id AS id_main, 
    cellphone AS cell_phone,
    cpf, 
    email,
    name, 
    version, 
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_kill_queue_raw.user