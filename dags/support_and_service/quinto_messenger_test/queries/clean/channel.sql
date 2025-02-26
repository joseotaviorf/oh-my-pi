SELECT
    id,
    channel_id AS id_channel,
    source_id AS id_session,
    source_uuid AS id_source_unique,
    channel_status,
    GET_JSON_OBJECT(channel_attributes,'$.channel_type') AS channel_type,
    user_phone,
    GET_JSON_OBJECT(channel_attributes,'$.twilioNumber') AS twilio_phone_number,
    CAST(GET_JSON_OBJECT(channel_resource,'$.messages_count') AS INT) AS number_of_messages,
    CAST(GET_JSON_OBJECT(channel_resource,'$.members_count') AS INT) AS number_of_members,
    channel_attributes,
    channel_resource,
    channel_proxy,
    source,
    CAST(GET_JSON_OBJECT(channel_attributes,'$.forwarding') AS BOOLEAN) AS is_forwarded,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_quinto_messenger_raw.channel
