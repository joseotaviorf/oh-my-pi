WITH events_filtered AS (
    SELECT
        SF_ALPHANUMERIC_SNAKE_CASE(event_type) AS event_type_sanitized,
        event_type,
        ts_event,
        id_user,
        id_amplitude,
        id_session,
        platform as amplitude_platform,
        FROM_JSON(event_properties,'
                house_id STRING,
                offer_id STRING,
                visit_code STRING,
                uri STRING') AS event_properties,
        FROM_JSON(user_properties,'
                entrance_uri STRING,
                platform STRING,
                gclid STRING,
                referrer STRING,
                utm_medium STRING,
                utm_source STRING,
                utm_campaign STRING,
                utm_content STRING,
                utm_term STRING,
                last_utm_medium STRING,
                last_utm_source STRING,
                last_utm_campaign STRING,
                last_utm_content STRING,
                last_utm_term STRING,
                `3fbf25d58c3cce92f0e6609904a37cc9` STRING,  -- app_platform column / event trigged by adjust
                `[adjust] app_version` STRING,
                `[adjust] adgroup` STRING,
                `[adjust] campaign` STRING,
                `[adjust] city` STRING,
                `[adjust] country` STRING,
                `[adjust] creative` STRING,
                `[adjust] impression_based` STRING,
                `[adjust] reattributed_at` STRING,
                `[adjust] installed_at` STRING,
                `[adjust] is_organic` STRING,
                `[adjust] tracking_enabled` STRING,
                `[adjust] tracking_limited` STRING,
                `[adjust] network` STRING') AS user_properties,
        year,
        month,
        day
    FROM
        datalake_amplitude_clean.events
    WHERE
      id_app = 170698
      AND year = {year}
      AND month = {month}
      AND day = {day}
)
SELECT
    event_type_sanitized,
    event_type,
    ts_event,
    id_user,
    id_amplitude,
    id_session,
    TRIM(event_properties.house_id) AS id_house,
    TRIM(COALESCE(
        event_properties.offer_id,
        REGEXP_EXTRACT(event_properties.uri,'(?<=\/(offer|aluguel)\/).*?(?=\/)',0)
    )) AS id_firestore,
    amplitude_platform,
    TRIM(event_properties.visit_code) AS visit_code,
    user_properties.entrance_uri AS entrance_uri,
    event_properties.uri AS uri_event_property,
    user_properties.utm_medium AS web_medium,
    user_properties.utm_source AS web_source,
    user_properties.utm_campaign AS web_campaign,
    user_properties.utm_content AS web_content,
    user_properties.utm_term AS web_term,
    user_properties.last_utm_medium AS web_last_medium,
    user_properties.last_utm_source AS web_last_source,
    user_properties.last_utm_campaign AS web_last_campaign,
    user_properties.last_utm_content AS web_last_content,
    user_properties.last_utm_term AS web_last_term,
    user_properties.`[adjust] app_version` AS adjust_app_version,
    user_properties.`[adjust] adgroup` AS adjust_adgroup,
    user_properties.`[adjust] campaign` AS adjust_campaign,
    user_properties.`[adjust] city` AS adjust_city,
    user_properties.`[adjust] country` AS adjust_country,
    user_properties.`[adjust] creative` AS adjust_creative,
    user_properties.`[adjust] impression_based` AS adjust_impression_based,
    user_properties.`[adjust] reattributed_at` AS adjust_reattributed_at,
    user_properties.`[adjust] installed_at` AS adjust_installed_at,
    user_properties.`[adjust] is_organic` AS adjust_is_organic,
    user_properties.`[adjust] tracking_enabled` AS adjust_tracking_enabled,
    user_properties.`[adjust] tracking_limited` AS adjust_tracking_limited,
    user_properties.`[adjust] network` AS adjust_network,
    user_properties.platform AS web_platform,
    user_properties.`3fbf25d58c3cce92f0e6609904a37cc9` AS app_platform,  -- app_platform column / event trigged by adjust
    user_properties.gclid AS gclid,
    user_properties.referrer AS referrer,
    year,
    month,
    day
FROM
    events_filtered