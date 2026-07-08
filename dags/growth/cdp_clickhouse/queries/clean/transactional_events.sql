SELECT
    raw.event_id AS id_event,
    raw.person_uuid AS id_person,
    TRY_CAST(raw.user_id AS BIGINT) AS id_user,
    COALESCE(
        get_json_object(raw.user_properties, '$.domain_user_id'),
        get_json_object(raw.enrichments, '$.domain_user_id')
    ) AS id_domain_user,
    COALESCE(
        get_json_object(raw.enrichments, '$.device_id'),
        get_json_object(raw.user_properties, '$.device_id')
    ) AS id_entity,
    COALESCE(
        CAST(raw.house_id AS STRING),
        get_json_object(raw.event_properties, '$.houseId')
    ) AS id_house,
    LOWER(raw.application) AS application,
    raw.journey_step,
    LOWER(raw.event_name) AS event_name,
    raw.event_properties,
    raw.user_properties,
    raw.timestamp_dt AS ts_event,
    TIMESTAMP_MILLIS(raw.egw_timestamp) AS ts_egw,
    MAKE_TIMESTAMP(
        YEAR(raw.timestamp_dt),
        MONTH(raw.timestamp_dt),
        DAY(raw.timestamp_dt),
        HOUR(raw.timestamp_dt),
        MINUTE(raw.timestamp_dt),
        0
    ) AS ts_kafka,
    CURRENT_TIMESTAMP() AS ts_load,
    raw.year,
    raw.month,
    raw.day
FROM
    datalake_cdp_raw.events_api AS raw
WHERE
    raw.egw_event_type = 'TRANSACTIONAL'
