WITH conversions AS (
    SELECT
        id_amplitude,
        id_user
    FROM
        datalake_amplitude_clean.170698_visit_schedule_confirmed_events
    WHERE 
        year = {year}
        AND month = {month}
        AND day = {day}
    UNION
    SELECT
        id_amplitude,
        id_user
    FROM
        datalake_amplitude_clean.170698_debug_visit_schedule_confirmed_events
    WHERE 
        year = {year}
        AND month = {month}
        AND day = {day}
    UNION
    SELECT
        id_amplitude,
        id_user
    FROM
        datalake_amplitude_clean.170698_offer_submitted_events
    WHERE 
        year = {year}
        AND month = {month}
        AND day = {day}
    UNION
    SELECT
        id_amplitude,
        id_user
    FROM
        datalake_amplitude_clean.170135_offer_submitted_events
    WHERE 
        year = {year}
        AND month = {month}
        AND day = {day}
    UNION
    SELECT
        id_amplitude,
        id_user
    FROM
        datalake_amplitude_clean.183049_offer_submitted_events
    WHERE 
        year = {year}
        AND month = {month}
        AND day = {day}
    UNION
    SELECT
        id_amplitude,
        id_user
    FROM
        datalake_amplitude_clean.170698_sale_offer_form_accepted_events
    WHERE 
        year = {year}
        AND month = {month}
        AND day = {day}
),
distinct_conversions AS (
    SELECT DISTINCT
        id_amplitude,
        id_user
    FROM
        conversions
    WHERE
        id_amplitude IS NOT NULL
),
ids_mapped_from_conversions AS (
    SELECT
        cvs.id_user,
        COALESCE(amu.id_amplitude,cvs.id_amplitude) AS id_amplitude,
        COALESCE(amu.id_amplitude_merged,cvs.id_amplitude) AS merged_amplitude_id
    FROM 
        distinct_conversions AS cvs
    JOIN 
        datalake_amplitude_clean.170698_user_merge AS amu
            ON cvs.id_amplitude = amu.id_amplitude_merged
    GROUP BY 1,2,3
    UNION
    SELECT
        id_user,
        id_amplitude,
        id_amplitude AS merged_amplitude_id
    FROM
        distinct_conversions
    GROUP BY 1,2,3
),
events_filtered AS (
    SELECT DISTINCT
        event_type_sanitized,
        event_type,
        ts_event,
        COALESCE(imc.id_user, evt.id_user) AS id_user,
        COALESCE(imc.merged_amplitude_id, evt.id_amplitude) AS id_amplitude,
        id_session,
        id_house,
        id_firestore,
        amplitude_platform,
        visit_code,
        entrance_uri,
        uri_event_property,
        web_medium,
        web_source,
        web_campaign,
        web_content,
        web_term,
        web_last_medium,
        web_last_source,
        web_last_campaign,
        web_last_content,
        web_last_term,
        adjust_app_version,
        adjust_adgroup,
        adjust_campaign,
        adjust_city,
        adjust_country,
        adjust_creative,
        adjust_impression_based,
        adjust_reattributed_at,
        adjust_installed_at,
        adjust_is_organic,
        adjust_tracking_enabled,
        adjust_tracking_limited,
        adjust_network,
        web_platform,
        app_platform,
        gclid,
        referrer,
        {year} as year,
        {month} as month,
        {day} as day
    FROM
        datalake_online_attribution.events_exploded AS evt
    JOIN
        ids_mapped_from_conversions AS imc 
            ON imc.id_amplitude = evt.id_amplitude
    WHERE
        DATE(CONCAT_WS("-",evt.year, evt.month, evt.day)) > DATE('{year}-{month}-{day}') - INTERVAL '4' month
),
events_mapped AS (
    SELECT
        event_type_sanitized,
        event_type,
        ts_event,
        id_user,
        id_amplitude,
        id_session,
        id_house,
        id_firestore,
        amplitude_platform,
        visit_code,
        entrance_uri,
        uri_event_property,
        web_medium,
        web_source,
        web_campaign,
        web_content,
        web_term,
        web_last_medium,
        web_last_source,
        web_last_campaign,
        web_last_content,
        web_last_term,
        adjust_app_version,
        adjust_adgroup,
        adjust_campaign,
        adjust_city,
        adjust_country,
        adjust_creative,
        adjust_impression_based,
        adjust_reattributed_at,
        adjust_installed_at,
        adjust_is_organic,
        adjust_tracking_enabled,
        adjust_tracking_limited,
        adjust_network,
        web_platform,
        app_platform,
        referrer,
        gclid,
        referrer,
        IF((UPPER(web_campaign) LIKE '%BRANDED%' OR UPPER(web_campaign) LIKE '%INSTITUCIONAL%') AND UPPER(web_campaign) NOT LIKE 'NON-BRANDED', 'Branded', 'Outro' ) AS web_branded,
        adjust_network AS app_source,
        adjust_campaign AS app_medium,
        COALESCE(
            NULLIF(
                CASE
                    WHEN web_platform in ("web_desktop", "web_mobile") THEN web_source
                    ELSE adjust_network
                END,
                "Organic"
            ),
            "organic"
        ) AS media_source,
        IF((UPPER(adjust_campaign) LIKE '%BRANDED%' OR UPPER(adjust_campaign) LIKE '%INSTITUCIONAL%') AND UPPER(adjust_campaign) NOT LIKE 'NON-BRANDED', 'Branded', 'Outro' ) AS app_branded,
        FIRST_VALUE(ts_event) OVER (PARTITION BY id_amplitude, web_medium, web_source, web_campaign, web_term, web_content, gclid ORDER BY ts_event) AS ts_web_attribution,
        FIRST_VALUE(ts_event) OVER (PARTITION BY id_amplitude, adjust_adgroup, adjust_campaign, adjust_creative, adjust_network, adjust_reattributed_at ORDER BY ts_event) AS ts_app_attribution,
        year,
        month,
        day
    FROM 
        events_filtered
)
SELECT
    event_type_sanitized,
    event_type,
    id_user,
    id_amplitude,
    id_session,
    id_house,
    id_firestore,
    visit_code,
    amplitude_platform,
    entrance_uri,
    uri_event_property,
    web_medium,
    web_source,
    web_campaign,
    web_content,
    web_term,
    web_last_medium,
    web_last_source,
    web_last_campaign,
    web_last_content,
    web_last_term,
    adjust_app_version,
    adjust_adgroup,
    adjust_campaign,
    adjust_city,
    adjust_country,
    adjust_creative,
    adjust_impression_based,
    adjust_reattributed_at,
    adjust_installed_at,
    adjust_is_organic,
    adjust_tracking_enabled,
    adjust_tracking_limited,
    adjust_network,
    referrer,
    gclid,
    web_branded,
    app_source,
    app_medium,
    app_branded,
    CASE
        WHEN ts_app_attribution>ts_web_attribution AND adjust_network != 'Organic' THEN app_platform
        WHEN ts_web_attribution>ts_app_attribution THEN web_platform
        WHEN (
            web_source IS NULL 
            AND web_medium IS NULL 
            AND web_campaign IS NULL 
            AND web_term IS NULL 
            AND web_content IS NULL
        ) THEN app_platform
        ELSE web_platform
    END AS platform,
    CASE
        WHEN ts_app_attribution>ts_web_attribution AND adjust_network != 'Organic' THEN app_source
        WHEN ts_web_attribution>ts_app_attribution THEN web_source
        WHEN (
            web_source IS NULL 
            AND web_medium IS NULL 
            AND web_campaign IS NULL 
            AND web_term IS NULL 
            AND web_content IS NULL
        ) THEN app_source
        ELSE web_source
    END AS utm_source,
    CASE
        WHEN ts_app_attribution>ts_web_attribution AND adjust_network != 'Organic' THEN app_medium
        WHEN ts_web_attribution>ts_app_attribution THEN web_medium
        WHEN (
            web_source IS NULL 
            AND web_medium IS NULL 
            AND web_campaign IS NULL 
            AND web_term IS NULL 
            AND web_content IS NULL
        ) THEN app_medium
        ELSE web_medium
    END AS utm_medium,
    CASE
        WHEN ts_app_attribution>ts_web_attribution AND adjust_network != 'Organic' THEN adjust_campaign
        WHEN ts_web_attribution>ts_app_attribution THEN web_campaign
        WHEN (
            web_source IS NULL 
            AND web_medium IS NULL 
            AND web_campaign IS NULL 
            AND web_term IS NULL 
            AND web_content IS NULL
         ) THEN adjust_campaign
        ELSE web_campaign
    END AS utm_campaign,
    CASE
        WHEN ts_app_attribution>ts_web_attribution AND adjust_network != 'Organic' THEN adjust_creative
        WHEN ts_web_attribution>ts_app_attribution THEN web_term
        WHEN (
            web_source IS NULL 
            AND web_medium IS NULL 
            AND web_campaign IS NULL 
            AND web_term IS NULL 
            AND web_content IS NULL
         ) THEN adjust_creative
        ELSE web_term
    END AS utm_term,
    CASE
        WHEN ts_app_attribution>ts_web_attribution AND adjust_network != 'Organic' THEN adjust_adgroup
        WHEN ts_web_attribution>ts_app_attribution THEN web_content
        WHEN (
            web_source IS NULL 
            AND web_medium IS NULL 
            AND web_campaign IS NULL 
            AND web_term IS NULL 
            AND web_content IS NULL
         ) THEN adjust_adgroup
        ELSE web_content
    END AS utm_content,
    CASE
        WHEN ts_app_attribution>ts_web_attribution AND adjust_network != 'Organic' THEN app_branded
        WHEN ts_web_attribution>ts_app_attribution THEN web_branded
        WHEN (
            web_source IS NULL 
            AND web_medium IS NULL 
            AND web_campaign IS NULL 
            AND web_term IS NULL 
            AND web_content IS NULL
         ) THEN app_branded
        ELSE web_branded
    END AS branded,
    media_source,
    ts_event,
    ts_web_attribution,
    ts_app_attribution,
    year,
    month,
    day
FROM
    events_mapped