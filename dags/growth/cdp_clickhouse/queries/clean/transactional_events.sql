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
    TIMESTAMP_MILLIS(raw.timestamp) AS ts_event,
    TIMESTAMP_MILLIS(raw.egw_timestamp) AS ts_egw,
    MAKE_TIMESTAMP(
        YEAR(TIMESTAMP_MILLIS(raw.timestamp)),
        MONTH(TIMESTAMP_MILLIS(raw.timestamp)),
        DAY(TIMESTAMP_MILLIS(raw.timestamp)),
        HOUR(TIMESTAMP_MILLIS(raw.timestamp)),
        MINUTE(TIMESTAMP_MILLIS(raw.timestamp)),
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
    AND MAKE_TIMESTAMP(raw.year, raw.month, raw.day, raw.hour, 0, 0) >= TIMESTAMP('{load_start_date}')
    AND MAKE_TIMESTAMP(raw.year, raw.month, raw.day, raw.hour, 0, 0) < TIMESTAMP('{load_end_date}')
