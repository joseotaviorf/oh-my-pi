SELECT
    raw.event_id AS id_event,
    raw.person_uuid AS id_person,
    CAST(raw.user_id AS STRING) AS id_user,
    COALESCE(
        get_json_object(raw.user_properties, '$.domain_user_id'),
        get_json_object(raw.enrichments, '$.domain_user_id')
    ) AS id_domain_user,
    COALESCE(
        get_json_object(raw.enrichments, '$.device_id'),
        get_json_object(raw.user_properties, '$.device_id')
    ) AS id_anonymous,
    get_json_object(raw.event_properties, '$.id_dispatch') AS id_dispatch,
    LOWER(get_json_object(raw.event_properties, '$.profile')) AS user_type,
    LOWER(get_json_object(raw.event_properties, '$.channel')) AS channel,
    LOWER(get_json_object(raw.event_properties, '$.context')) AS comms_type,
    LOWER(get_json_object(raw.event_properties, '$.category')) AS comms_typology,
    LOWER(get_json_object(raw.event_properties, '$.journeyStep')) AS comms_journey_step,
    LOWER(get_json_object(raw.event_properties, '$.status')) AS comms_status,
    LOWER(get_json_object(raw.event_properties, '$.referenceName')) AS comms_name,
    LOWER(get_json_object(raw.event_properties, '$.rule')) AS comms_rule,
    LOWER(get_json_object(raw.event_properties, '$.action')) AS comms_action,
    LOWER(get_json_object(raw.event_properties, '$.templateName')) AS comms_template,
    LOWER(raw.application) AS comms_source,
    raw.event_properties,
    raw.user_properties,
    raw.event_name,
    MAKE_TIMESTAMP(
        YEAR(raw.timestamp_dt),
        MONTH(raw.timestamp_dt),
        DAY(raw.timestamp_dt),
        HOUR(raw.timestamp_dt),
        MINUTE(raw.timestamp_dt),
        0
    ) AS ts_kafka,
    raw.timestamp_dt AS ts_event,
    TIMESTAMP_MILLIS(raw.egw_timestamp) AS ts_egw,
    CURRENT_TIMESTAMP() AS ts_load,
    raw.year,
    raw.month,
    raw.day
FROM
    datalake_cdp_raw.events_api AS raw
WHERE
    raw.egw_event_type = 'COMMUNICATION'
    AND MAKE_TIMESTAMP(raw.year, raw.month, raw.day, raw.hour, 0, 0) >= TIMESTAMP('{load_start_date}')
    AND MAKE_TIMESTAMP(raw.year, raw.month, raw.day, raw.hour, 0, 0) < TIMESTAMP('{load_end_date}')
