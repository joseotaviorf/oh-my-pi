SELECT
    id AS id_portfolio,
    worker_id AS id_worker,
    user_identifier AS id_user,
    id_contract,
    id_entity_origin,
    context_identifier, 
    user_identifier_type,
    chat_uuid AS id_chat,
    status,
    context_group AS entity_origin_name,
    entity_origin_persona,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hefesto_raw.worker_portfolio
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
