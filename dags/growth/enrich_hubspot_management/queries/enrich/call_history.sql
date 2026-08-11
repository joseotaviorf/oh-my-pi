SELECT
    CAST(id_call AS BIGINT) AS id_call,
    CAST(GET_JSON_OBJECT(properties, '$.hubspot_owner_id') AS BIGINT) AS id_hubspot_owner,
    CAST(GET_JSON_OBJECT(properties, '$.hs_call_callee_object_id') AS BIGINT) AS id_call_callee_object,
    TRANSFORM(
        SPLIT(NULLIF(GET_JSON_OBJECT(properties, '$.hs_attachment_ids'), ''), ';'),
        x -> CAST(x AS BIGINT)
    ) AS ids_attachments,
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
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_call_title'), '') AS call_title,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_call_body'), '') AS call_body,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_call_status'), '') AS call_status,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_activity_type'), '') AS activity_type,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_call_direction'), '') AS call_direction,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_call_callee_object_type_id'), '') AS call_callee_object_type,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_call_disposition'), '') AS call_disposition,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_call_from_number'), '') AS call_from_number,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_call_to_number'), '') AS call_to_number,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_call_recording_url'), '') AS call_recording_url,
    CAST(NULLIF(GET_JSON_OBJECT(properties, '$.hs_call_duration'), '') AS INT) AS call_duration_in_ms,
    CAST(NULLIF(GET_JSON_OBJECT(properties, '$.hs_timestamp'), '') AS TIMESTAMP) AS ts_call,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    datalake_hubspot_clean.call
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
