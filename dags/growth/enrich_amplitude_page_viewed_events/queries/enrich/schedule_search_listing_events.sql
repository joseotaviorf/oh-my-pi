SELECT
    'schedule_page_viewed' AS tof_event_type,
    ep_house_id,
    NULL AS id_region,
    id_user,
    id_amplitude,
    id_device,
    id_session,
    business_context,
    entrance_uri,
    referrer,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_term,
    utm_content,
    up_platform,
    top5_house_id,
    False AS is_qac,
    False AS is_qac_region,
    NULL AS uri,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.170698_schedule_page_viewed_events
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
UNION ALL
SELECT
    'search_page_viewed' AS tof_event_type,
    id_house AS ep_house_id,
    NULL AS id_region,
    id_user,
    id_amplitude,
    id_device,
    id_session,
    business_context,
    entrance_uri,
    referrer,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_term,
    utm_content,
    up_platform,
    top5_house_id,
    is_qac,
    is_qac_region,
    uri,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.170698_search_page_viewed_events
WHERE
    country IN (
        'Brazil',
        'Mexico',
        'Argentina',
        'Colombia',
        'Peru',
        'Chile',
        'Venezuela',
        'Ecuador',
        'Bolivia',
        'Paraguay',
        'Uruguay',
        'Panama',
        'Dominican Republic',
        'Costa Rica'
    )
    AND MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
UNION ALL
SELECT
    'search_results_page_viewed' AS tof_event_type,
    ep_house_id,
    NULL AS id_region,
    id_user,
    id_amplitude,
    id_device,
    id_session,
    business_context,
    entrance_uri,
    referrer,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_term,
    utm_content,
    up_platform,
    top5_house_id,
    is_qac,
    is_qac_region,
    uri,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.170698_search_results_page_viewed_events
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
UNION ALL
SELECT
    'listing_page_viewed' AS tof_event_type,
    ep_house_id,
    id_region,
    id_user,
    id_amplitude,
    id_device,
    id_session,
    business_context,
    entrance_uri,
    referrer,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_term,
    utm_content,
    up_platform,
    top5_house_id,
    is_qac,
    is_qac_region,
    uri,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.170698_listing_page_viewed_events
WHERE
    country IN (
        'Brazil',
        'Mexico',
        'Argentina',
        'Colombia',
        'Peru',
        'Chile',
        'Venezuela',
        'Ecuador',
        'Bolivia',
        'Paraguay',
        'Uruguay',
        'Panama',
        'Dominican Republic',
        'Costa Rica'
    )
    AND MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
