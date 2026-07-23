WITH deduplicated_offer_events AS (
    SELECT
        id_user,
        id_app,
        ep_id_house AS id_house,
        ep_id_firestore AS id_firestore,
        country AS user_country,
        user_properties,
        up_app_type AS app_type,
        version_name,
        up_utm_source AS utm_source,
        up_utm_medium AS utm_medium,
        up_utm_campaign AS utm_campaign,
        up_utm_content AS utm_content,
        up_utm_term AS utm_term,
        up_entrance_uri AS entrance_uri,
        dt_event,
        ts_event,
        year,
        month,
        day
    FROM
        datalake_amplitude_clean.170698_offer_submitted_events
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND  DATE('{load_end_date}')
    UNION
    SELECT
        id_user,
        id_app,
        ep_id_house AS id_house,
        ep_id_firestore AS id_firestore,
        country AS user_country,
        user_properties,
        up_app_type AS app_type,
        version_name,
        up_utm_source AS utm_source,
        up_utm_medium AS utm_medium,
        up_utm_campaign AS utm_campaign,
        up_utm_content AS utm_content,
        up_utm_term AS utm_term,
        up_entrance_uri AS entrance_uri,
        dt_event,
        ts_event,
        year,
        month,
        day
    FROM
        datalake_amplitude_clean.183049_offer_submitted_events
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION
    -- New offer submitted events (Q3/2024)
    SELECT
        id_user,
        id_app,
        ep_id_house AS id_house,
        ep_id_firestore AS id_firestore,
        country AS user_country,
        user_properties,
        up_app_type AS app_type,
        version_name,
        up_utm_source AS utm_source,
        up_utm_medium AS utm_medium,
        up_utm_campaign AS utm_campaign,
        up_utm_content AS utm_content,
        up_utm_term AS utm_term,
        up_entrance_uri AS entrance_uri,
        dt_event,
        ts_event,
        year,
        month,
        day
    FROM
        datalake_amplitude_clean.170698_offer_submitted_new_events
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION
    SELECT
        id_user,
        id_app,
        ep_id_house AS id_house,
        ep_id_firestore AS id_firestore,
        country AS user_country,
        user_properties,
        up_app_type AS app_type,
        version_name,
        up_utm_source AS utm_source,
        up_utm_medium AS utm_medium,
        up_utm_campaign AS utm_campaign,
        up_utm_content AS utm_content,
        up_utm_term AS utm_term,
        up_entrance_uri AS entrance_uri,
        dt_event,
        ts_event,
        year,
        month,
        day
    FROM
        datalake_amplitude_clean.183047_offer_submitted_new_events
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    CAST(id_user AS BIGINT) AS id_user,
    CAST(id_house AS BIGINT) AS id_house,
    id_app,
    id_firestore,
    GET_JSON_OBJECT(user_properties, '$.country') AS country_code,
    user_country,
    app_type,
    version_name,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_content,
    utm_term,
    entrance_uri,
    CASE
        WHEN (UPPER(utm_campaign) LIKE '%BRANDED%'
        OR UPPER(utm_campaign) LIKE '%INSTITUCIONAL%')
        AND UPPER(utm_campaign) NOT LIKE '%NON-BRANDED%'
            THEN 'Branded'
        ELSE 'Outro'
    END AS branded,
    COALESCE(((UPPER(utm_campaign) LIKE '%BRANDED%'
        OR UPPER(utm_campaign) LIKE '%INSTITUCIONAL%')
        AND LOWER(utm_campaign) NOT LIKE '%non-branded%'), FALSE) AS is_branded,
    dt_event,
    ts_event,
    year,
    month,
    day
FROM
    deduplicated_offer_events