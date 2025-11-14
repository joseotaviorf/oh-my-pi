SELECT
    get_json_object(event_properties, '$.house_id') AS id_house,
    id_user,
    get_json_object(event_properties, '$.recset_id') AS id_recset,
    business_context,
    up_platform AS platform,
    CASE
        WHEN up_platform IN ("android", "ios") THEN "app"
        WHEN up_platform IN ("web_desktop", "web_mobile") THEN "web"
        ELSE "N/A"
    END AS platform_grouped,
    CASE
        WHEN up_platform IN ("android", "ios", "web_mobile") THEN "mobile"
        WHEN up_platform IN ("web_desktop") THEN "desktop"
        ELSE "N/A"
    END AS device_type,
    city AS user_city,
    region AS user_region,
    country AS user_country,
    get_json_object(event_properties, '$.city') AS house_city,
    get_json_object(event_properties, '$.macro_region') AS house_macro_region,
    get_json_object(event_properties, '$.state') AS house_state,
    get_json_object(event_properties, '$.country') AS house_country,
    get_json_object(event_properties, '$.from_route') AS lpv_from_route,
    get_json_object(event_properties, '$.recset_showcase') AS recset_showcase,
    get_json_object(event_properties, '$.valor_total') AS rent_total_value,
    get_json_object(event_properties, '$.valor_venda') AS sale_value,
    get_json_object(event_properties, '$.recset_id') IS NOT NULL AS is_recommendation,
    ts_event,
    DATE(ts_event) AS dt_event,
    DATE_TRUNC('week', ts_event) AS ts_event_week,
    DATE_TRUNC('month', ts_event) AS ts_event_month,
    DATE_TRUNC('quarter', ts_event) AS ts_event_quarter,
    year,
    month,
    day
FROM datalake_amplitude_clean.170698_listing_page_viewed_events
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_7}) AND DATE('{end_date}')
    AND business_context IN ('rent', 'sale')
