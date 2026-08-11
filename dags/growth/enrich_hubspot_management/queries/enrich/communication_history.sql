SELECT
    CAST(id_communication AS BIGINT) AS id_communication,
    TRANSFORM(
        FROM_JSON(GET_JSON_OBJECT(associations, '$.tickets.results'), 'array<struct<id:string, type:string>>').id,
        x -> CAST(x AS BIGINT)
    ) AS ids_associated_tickets,
    TRANSFORM(
        FROM_JSON(GET_JSON_OBJECT(associations, '$.contacts.results'), 'array<struct<id:string, type:string>>').id,
        x -> CAST(x AS BIGINT)
    ) AS ids_associated_contacts,
    TRANSFORM(
        FROM_JSON(GET_JSON_OBJECT(associations, '$.companies.results'), 'array<struct<id:string, type:string>>').id,
        x -> CAST(x AS BIGINT)
    ) AS ids_associated_companies,
    TRANSFORM(
        FROM_JSON(GET_JSON_OBJECT(associations, '$.deals.results'), 'array<struct<id:string, type:string>>').id,
        x -> CAST(x AS BIGINT)
    ) AS ids_associated_deals,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_communication_channel_type'), '') AS communication_channel_type,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_communication_logged_from'), '') AS communication_logged_from,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_communication_body'), '') AS communication_body,
    CAST(NULLIF(GET_JSON_OBJECT(properties, '$.hs_timestamp'), '') AS TIMESTAMP) AS ts_communication,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    datalake_hubspot_clean.communication
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
