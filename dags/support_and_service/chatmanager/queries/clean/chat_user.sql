SELECT
    id,
    uuid,
    participant_id AS id_participant,
    origin_id AS id_origin,
    origin_type,
    attributes,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_chatmanager_raw.chatuser
