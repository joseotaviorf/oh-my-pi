SELECT
    id_meeting::BIGINT,
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
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_meeting_title'), '') AS meeting_title,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_meeting_body'), '') AS meeting_body,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_internal_meeting_notes'), '') AS internal_meeting_notes,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_meeting_external_url'), '') AS meeting_external_url,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_meeting_location'), '') AS meeting_location,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_meeting_outcome'), '') AS meeting_outcome,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_activity_type'), '') AS activity_type,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_meeting_start_time'), '')::TIMESTAMP AS ts_meeting_start,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_meeting_end_time'), '')::TIMESTAMP AS ts_meeting_end,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_timestamp'), '')::TIMESTAMP AS ts_meeting,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    datalake_hubspot_clean.meeting
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
