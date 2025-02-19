SELECT
    CAST(id AS BIGINT) AS id,
    CAST(main_id AS BIGINT) AS id_main, 
    CAST(cellphone AS STRING) AS cell_phone,
    CAST(cpf AS STRING) AS cpf, 
    CAST(email AS STRING) AS email,
    CAST(name AS STRING) AS name, 
    CAST(version AS SMALLINT) AS version, 
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year, 
    month,
    day
FROM
    datalake_kill_queue_raw.user