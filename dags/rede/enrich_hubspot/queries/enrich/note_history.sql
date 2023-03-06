SELECT
    id_note::BIGINT,
    GET_JSON_OBJECT(properties, '$.hubspot_owner_id')::BIGINT AS id_hubspot_owner,
    TRANSFORM(
        SPLIT(NULLIF(GET_JSON_OBJECT(properties, '$.hs_attachment_ids'), ''), ';'),
        x -> x::BIGINT
    ) AS ids_attachments,
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
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_note_body'), '') AS note_body,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_timestamp'), '')::TIMESTAMP AS ts_note,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    datalake_hubspot_clean.note
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
