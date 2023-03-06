SELECT
    id_task::BIGINT,
    GET_JSON_OBJECT(properties, '$.hubspot_owner_id')::BIGINT AS id_hubspot_owner,
    TRANSFORM(
        FROM_JSON(GET_JSON_OBJECT(associations, '$.tickets.results'), 'array<struct<id:string, type:string>>').id,
        x -> x::BIGINT
    ) AS ids_associated_tickets,
    TRANSFORM(
        FROM_JSON(GET_JSON_OBJECT(associations, '$.contacts.results'), 'array<struct<id:string, type:string>>').id,
        x -> x::BIGINT
    ) AS ids_associated_contacts,
    TRANSFORM(
        FROM_JSON(GET_JSON_OBJECT(associations, '$.companies.results'), 'array<struct<id:string, type:string>>').id,
        x -> x::BIGINT
    ) AS ids_associated_companies,
    TRANSFORM(
        FROM_JSON(GET_JSON_OBJECT(associations, '$.deals.results'), 'array<struct<id:string, type:string>>').id,
        x -> x::BIGINT
    ) AS ids_associated_deals,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_task_body'), '') AS task_body,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_task_subject'), '') AS task_subject,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_task_status'), '') AS task_status,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_task_type'), '') AS task_type,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_task_priority'), '') AS task_priority,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_timestamp'), '')::TIMESTAMP AS ts_task_due_date,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    datalake_hubspot_clean.task
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
