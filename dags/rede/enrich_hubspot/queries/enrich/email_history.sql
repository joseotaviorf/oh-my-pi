SELECT
    id_email::BIGINT,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_unique_id'), '') AS id_unique,
    NULLIF(GET_JSON_OBJECT(properties, '$.hubspot_owner_id'), '')::BIGINT AS id_owner_hubspot,
    TRANSFORM(
        SPLIT(NULLIF(GET_JSON_OBJECT(properties, '$.hs_all_owner_ids'), ''), ';'),
        x -> x::BIGINT
    ) AS ids_all_owners,
    TRANSFORM(
        SPLIT(NULLIF(GET_JSON_OBJECT(properties, '$.hs_user_ids_of_all_owners'), ''), ';'),
        x -> x::BIGINT
    ) AS id_user_of_all_owners,
    NULLIF(GET_JSON_OBJECT(properties, '$.hubspot_team_id'), '') AS id_hubspot_team,
    TRANSFORM(
        SPLIT(NULLIF(GET_JSON_OBJECT(properties, '$.hs_all_team_ids'), ''), ';'),
        x -> x::BIGINT
    ) AS ids_all_teams,
    TRANSFORM(
        SPLIT(NULLIF(GET_JSON_OBJECT(properties, '$.hs_all_accessible_team_ids'), ''), ';'),
        x -> x::BIGINT
    ) AS ids_all_accessible_teams,
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
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_created_by'), '')::BIGINT AS id_created_by,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_created_by_user_id'), '')::BIGINT AS id_user_created_by,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_modified_by'), '')::BIGINT AS id_modified_by,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_updated_by_user_id'), '')::BIGINT AS id_user_modified_by,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_direction_and_unique_id'), '') AS id_unique_and_direction,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_message_id'), '') AS id_email_message,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_thread_id'), '') AS id_email_thread,
    TRANSFORM(
        SPLIT(NULLIF(GET_JSON_OBJECT(properties, '$.hs_attachment_ids'), ''), ';'),
        x -> x::BIGINT
    ) AS ids_attachments,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_facsimile_send_id'), '') AS id_email_facsimile_send,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_headers'), '') AS headers,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_subject'), '') AS subject,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_text'), '') AS text,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_html'), '') AS html,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_body_preview'), '') AS body_preview,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_body_preview_html'), '') AS body_preview_html,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_direction'), '') AS direction,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_engagement_source'), '') AS engagement_source,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_logged_from'), '') AS logged_from,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_sent_via'), '') AS sent_via,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_status'), '') AS status,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_post_send_status'), '') AS post_send_status,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_media_processing_status'), '') AS media_processing_status,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_sender_email'), '') AS sender_email,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_from_raw'), '') AS from_raw,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_from_email'), '') AS from_email,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_from_firstname'), '') AS from_first_name,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_from_lastname'), '') AS from_last_name,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_to_raw'), '') AS to_raw,
    SPLIT(NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_to_email'), ''), ';') AS to_emails,
    SPLIT(NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_to_firstname'), ''), ';') AS to_first_names,
    SPLIT(NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_to_lastname'), ''), ';') AS to_last_names,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_cc_raw'), '') AS cc_raw,
    SPLIT(NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_cc_email'), ''), ';') AS cc_emails,
    SPLIT(NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_cc_firstname'), ''), ';') AS cc_first_names,
    SPLIT(NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_cc_lastname'), ''), ';') AS cc_last_names,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_tracker_key'), '') AS tracker_key,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_error_message'), '') AS error_message,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_gdpr_deleted'), '')::BOOLEAN AS is_gdpr_deleted,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_body_preview_is_truncated'), '')::BOOLEAN AS is_body_preview_truncated,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_attached_video_opened'), '')::BOOLEAN AS is_email_attached_video_opened,
    NULLIF(GET_JSON_OBJECT(properties, '$.hs_email_attached_video_watched'), '')::BOOLEAN AS is_email_attached_video_watched,
    NULLIF(GET_JSON_OBJECT(properties, '$.hubspot_owner_assigneddate'), '') AS ts_hubspot_owner_assigned,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    datalake_hubspot_clean.email
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
