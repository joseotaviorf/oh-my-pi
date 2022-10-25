SELECT
    GET_JSON_OBJECT(REPLACE(_id, '$', ''), '$.oid') AS id,
    GET_JSON_OBJECT(REPLACE(entity_id, '$', ''), '$.oid') AS id_entity,
    collection AS collection_name,
    entity_data,
    query,
    operation AS operation_type,
    BOOLEAN(status) AS is_status,
    CAST(GET_JSON_OBJECT(REPLACE(revision_date, '$', ''), '$.date') AS TIMESTAMP) AS ts_revised,
    year,
    month,
    day
FROM 
    datalake_cidade_alerta_raw.audit
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
