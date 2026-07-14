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
    ) AS id_anonymous,
    raw.event_name,
    LOWER(raw.application) AS application,
    COALESCE(
        get_json_object(raw.event_properties, '$.platform'),
        get_json_object(raw.user_properties, '$.platform')
    ) AS platform,
    get_json_object(raw.event_properties, '$.market') AS country,
    get_json_object(raw.event_properties, '$.address.city') AS city,
    get_json_object(raw.event_properties, '$.region') AS region,
    get_json_object(raw.event_properties, '$.os_name') AS app_type,
    get_json_object(raw.event_properties, '$.device_manufacturer') AS device_info,
    get_json_object(raw.event_properties, '$.ip_address') AS ip_address,
    TRY_CAST(get_json_object(raw.event_properties, '$.address.lat') AS DOUBLE) AS latitude,
    TRY_CAST(get_json_object(raw.event_properties, '$.address.lng') AS DOUBLE) AS longitude,
    get_json_object(raw.user_properties, '$.egw_initial_gclid') AS egw_initial_gclid,
    get_json_object(raw.user_properties, '$.egw_initial_fbclid') AS egw_initial_fbclid,
    get_json_object(raw.user_properties, '$.egw_initial_gbraid') AS egw_initial_gbraid,
    get_json_object(raw.user_properties, '$.egw_initial_wbraid') AS egw_initial_wbraid,
    get_json_object(raw.user_properties, '$.egw_gclid') AS egw_gclid,
    get_json_object(raw.user_properties, '$.egw_fbclid') AS egw_fbclid,
    get_json_object(raw.user_properties, '$.egw_gbraid') AS egw_gbraid,
    get_json_object(raw.user_properties, '$.egw_wbraid') AS egw_wbraid,
    get_json_object(raw.user_properties, '$.egw_rdt_cid') AS egw_rdt_cid,
    get_json_object(raw.user_properties, '$.egw_initial_rdt_cid') AS egw_initial_rdt_cid,
    get_json_object(raw.user_properties, '$.egw_msclkid') AS egw_msclkid,
    get_json_object(raw.user_properties, '$.egw_initial_msclkid') AS egw_initial_msclkid,
    get_json_object(raw.user_properties, '$.egw_apps_flyer_id') AS egw_apps_flyer_id,
    get_json_object(raw.user_properties, '$.egw_initial_utm_campaign') AS egw_initial_utm_campaign,
    get_json_object(raw.user_properties, '$.egw_initial_utm_content') AS egw_initial_utm_content,
    get_json_object(raw.user_properties, '$.egw_initial_utm_medium') AS egw_initial_utm_medium,
    get_json_object(raw.user_properties, '$.egw_initial_utm_source') AS egw_initial_utm_source,
    get_json_object(raw.user_properties, '$.egw_initial_utm_term') AS egw_initial_utm_term,
    get_json_object(raw.user_properties, '$.egw_utm_campaign') AS egw_utm_campaign,
    get_json_object(raw.user_properties, '$.egw_utm_content') AS egw_utm_content,
    get_json_object(raw.user_properties, '$.egw_utm_medium') AS egw_utm_medium,
    get_json_object(raw.user_properties, '$.egw_utm_source') AS egw_utm_source,
    get_json_object(raw.user_properties, '$.egw_utm_term') AS egw_utm_term,
    CASE
        WHEN get_json_object(raw.user_properties, '$.egw_initial_attribution_time') IS NOT NULL
        THEN TIMESTAMP_MILLIS(
            CAST(get_json_object(raw.user_properties, '$.egw_initial_attribution_time') AS BIGINT)
        )
    END AS egw_initial_attribution_time,
    CASE
        WHEN get_json_object(raw.user_properties, '$.egw_last_attribution_time') IS NOT NULL
        THEN TIMESTAMP_MILLIS(
            CAST(get_json_object(raw.user_properties, '$.egw_last_attribution_time') AS BIGINT)
        )
    END AS egw_last_attribution_time,
    get_json_object(raw.user_properties, '$.egw_linked_devices') AS egw_linked_devices,
    raw.event_properties,
    raw.user_properties,
    MAKE_TIMESTAMP(
        YEAR(TIMESTAMP_MILLIS(raw.timestamp)),
        MONTH(TIMESTAMP_MILLIS(raw.timestamp)),
        DAY(TIMESTAMP_MILLIS(raw.timestamp)),
        HOUR(TIMESTAMP_MILLIS(raw.timestamp)),
        MINUTE(TIMESTAMP_MILLIS(raw.timestamp)),
        0
    ) AS ts_kafka,
    TIMESTAMP_MILLIS(raw.timestamp) AS ts_event,
    TIMESTAMP_MILLIS(raw.egw_timestamp) AS ts_egw,
    CURRENT_TIMESTAMP() AS ts_load,
    raw.year,
    raw.month,
    raw.day
FROM
    datalake_cdp_raw.events_api AS raw
WHERE
    raw.egw_event_type = 'USER_TRACKING'
    AND MAKE_TIMESTAMP(raw.year, raw.month, raw.day, raw.hour, 0, 0) >= TIMESTAMP('{load_start_date}')
    AND MAKE_TIMESTAMP(raw.year, raw.month, raw.day, raw.hour, 0, 0) < TIMESTAMP('{load_end_date}')
