SELECT
    id AS id_portfolio,
    worker_id AS id_worker,
    COALESCE(user_id, user_identifier) AS id_user,
    contract_id as id_contract,
    entity_origin_id AS id_entity_origin,
    context_identifier, 
    user_identifier_type,
    chat_uuid AS id_chat,
    status,
    entity_origin_name as entity_origin,
    context_group as entity_origin_name,
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
