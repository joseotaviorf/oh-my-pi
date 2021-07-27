SELECT
    id,
    main_id AS id_main, 
    cellphone AS cell_phone,
    cpf, 
    email,
    name, 
    version, 
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year, 
    month,
    day
FROM
    datalake_kill_queue_raw.user
WHERE 
    year = {year}
    AND month = {month}
    AND day = {day}