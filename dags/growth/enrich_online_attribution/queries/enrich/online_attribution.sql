WITH conversions AS (
    SELECT
        id_amplitude,
        id_user
    FROM
        datalake_amplitude_clean.170698_visit_schedule_confirmed_events
    WHERE 
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION
    SELECT
        id_amplitude,
        id_user
    FROM
        datalake_amplitude_clean.170698_debug_visit_schedule_confirmed_events
    WHERE 
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION
    SELECT
        id_amplitude,
        id_user
    FROM
        datalake_amplitude_clean.170698_offer_submitted_events
    WHERE 
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION
    SELECT
        id_amplitude,
        id_user
    FROM
        datalake_amplitude_clean.183049_offer_submitted_events
    WHERE 
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    -- New offer submitted events
    UNION
    SELECT
        id_amplitude,
        id_user
    FROM
        datalake_amplitude_clean.170698_offer_submitted_new_events -- IQ Prod new events
    WHERE 
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION
    SELECT
        id_amplitude,
        id_user
    FROM
        datalake_amplitude_clean.183047_offer_submitted_new_events -- PP Prod new events
    WHERE 
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION
    SELECT
        id_amplitude,
        id_user
    FROM
        datalake_amplitude_clean.170698_sale_offer_form_accepted_events
    WHERE 
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
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
    SELECT
        ts_event,
        event_type_sanitized,
        COALESCE(imc.id_user, evt.id_user) AS id_user,
        COALESCE(imc.merged_amplitude_id, evt.id_amplitude) AS id_amplitude,
        id_session,
        id_house,
        id_firestore,
        visit_code,
        amplitude_platform,
        gclid,
        entrance_uri,
        referrer,
        business_context,
        attributed_at,
        web_medium,
        web_source,
        web_campaign,
        web_content,
        web_term,
        web_platform,
        CASE
            WHEN appsflyer_campaign = 'N/A' THEN adjust_adgroup
            ELSE appsflyer_adset
        END AS adjust_adgroup,
        CASE
            WHEN appsflyer_campaign = 'N/A' THEN adjust_campaign
            ELSE appsflyer_campaign
        END AS adjust_campaign,
        CASE
            WHEN appsflyer_campaign = 'N/A' THEN adjust_creative
            ELSE appsflyer_ad
        END AS adjust_creative,
        CASE
            WHEN appsflyer_campaign = 'N/A' THEN adjust_reattributed_at
            ELSE NULL
        END AS adjust_reattributed_at,
        CASE
            WHEN appsflyer_campaign = 'N/A' THEN adjust_network
            ELSE appsflyer_media_source
        END AS adjust_network,
        app_platform
    FROM
        datalake_online_attribution.events_exploded AS evt
    JOIN
        ids_mapped_from_conversions AS imc 
            ON imc.id_amplitude = evt.id_amplitude
    WHERE
         MAKE_DATE(evt.year, evt.month, evt.day) > DATE('{load_end_date}') - INTERVAL '4' MONTH 
    GROUP BY 
        1,2,3,4,5,6,7,8,9,10,11,12,
        13,14,15,16,17,18,19,20,21,22,23,24,25,26
),
events_app AS (
    SELECT
        event_type_sanitized,
        ts_event,
        id_user,
        id_amplitude,
        id_session,
        entrance_uri,
        referrer,
        business_context,
        id_house,
        id_firestore,
        visit_code,
        amplitude_platform,
        adjust_adgroup,
        adjust_campaign,
        adjust_creative,
        adjust_reattributed_at,
        adjust_network,
        app_platform,
        IF((UPPER(adjust_campaign) LIKE '%BRANDED%' OR UPPER(adjust_campaign) LIKE '%INSTITUCIONAL%') AND UPPER(adjust_campaign) NOT LIKE 'NON-BRANDED', 'Branded', 'Outro' ) AS app_branded,
        FIRST_VALUE(ts_event) OVER (PARTITION BY id_amplitude, adjust_adgroup, adjust_campaign, adjust_creative, adjust_network, adjust_reattributed_at ORDER BY ts_event) AS ts_app_attribution
    FROM 
        events_filtered
    WHERE
        (adjust_network <> 'Organic')
        OR (adjust_network = 'Organic' AND adjust_campaign IS NOT NULL)
),
events_web AS (
    SELECT
        event_type_sanitized,
        ts_event,
        id_user,
        id_amplitude,
        id_session,
        entrance_uri,
        referrer,
        business_context,
        attributed_at,
        id_house,
        id_firestore,
        visit_code,
        amplitude_platform,
        gclid AS web_gclid,
        web_medium,
        web_source,
        web_campaign,
        web_content,
        web_term,
        web_platform,
        IF((UPPER(web_campaign) LIKE '%BRANDED%' OR UPPER(web_campaign) LIKE '%INSTITUCIONAL%') AND UPPER(web_campaign) NOT LIKE 'NON-BRANDED', 'Branded', 'Outro' ) AS web_branded,
        FIRST_VALUE(ts_event) OVER (PARTITION BY id_amplitude, web_medium, web_source, web_campaign, web_term, web_content, gclid ORDER BY ts_event) AS ts_web_attribution
    FROM 
        events_filtered
)
SELECT
    COALESCE(web.id_user, app.id_user) AS id_user,
    COALESCE(web.id_amplitude, app.id_amplitude) AS id_amplitude,
    COALESCE(web.id_session, app.id_session) AS id_session,
    COALESCE(web.id_house, app.id_house) AS id_house,
    COALESCE(web.id_firestore, app.id_firestore) AS id_firestore,
    COALESCE(web.visit_code, app.visit_code) AS visit_code,
    COALESCE(web.amplitude_platform, app.amplitude_platform) AS amplitude_platform,
    COALESCE(web.event_type_sanitized, app.event_type_sanitized) AS event_type_sanitized,
    COALESCE(web.entrance_uri, app.entrance_uri) AS entrance_uri,
    COALESCE(web.referrer, app.referrer) AS referrer,
    COALESCE(web.business_context, app.business_context) AS business_context,
    attributed_at,
    web_gclid,
    web_medium,
    web_source,
    web_campaign,
    web_content,
    web_term,
    web_platform,
    web_branded,
    adjust_adgroup,
    adjust_campaign,
    adjust_creative,
    adjust_reattributed_at,
    adjust_network,
    app_platform,
    app_branded,
    CASE
        WHEN ts_app_attribution>ts_web_attribution THEN app_platform
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
        WHEN ts_app_attribution>ts_web_attribution THEN adjust_network
        WHEN ts_web_attribution>ts_app_attribution THEN web_source
        WHEN (
            web_source IS NULL 
            AND web_medium IS NULL 
            AND web_campaign IS NULL 
            AND web_term IS NULL 
            AND web_content IS NULL
        ) THEN adjust_network
        ELSE web_source
    END AS utm_source,
    CASE
        WHEN ts_app_attribution>ts_web_attribution THEN adjust_campaign
        WHEN ts_web_attribution>ts_app_attribution THEN web_medium
        WHEN (
            web_source IS NULL 
            AND web_medium IS NULL 
            AND web_campaign IS NULL 
            AND web_term IS NULL 
            AND web_content IS NULL
        ) THEN adjust_campaign
        ELSE web_medium
    END AS utm_medium,
    CASE
        WHEN ts_app_attribution>ts_web_attribution THEN adjust_campaign
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
        WHEN ts_app_attribution>ts_web_attribution THEN adjust_creative
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
        WHEN ts_app_attribution>ts_web_attribution THEN adjust_adgroup
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
        WHEN ts_app_attribution>ts_web_attribution THEN app_branded
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
    COALESCE(LOWER(IF(web_platform IN ("web_desktop", "web_mobile"), web_source, adjust_network)), 'organic') AS media_source,
    COALESCE(web.ts_event, app.ts_event) AS ts_event,
    ts_web_attribution,
    ts_app_attribution,
    YEAR('{load_end_date}') AS year,
    MONTH('{load_end_date}') AS month,
    DAY('{load_end_date}') AS day
FROM
    events_web web
FULL OUTER JOIN events_app AS app
    ON web.event_type_sanitized = app.event_type_sanitized
    AND web.ts_event = app.ts_event
    AND web.id_user = app.id_user
    AND web.id_amplitude = app.id_amplitude
    AND web.id_session = app.id_session 
    AND web.id_house = app.id_house
    AND web.id_firestore = app.id_firestore
    AND web.visit_code = app.visit_code
    AND web.amplitude_platform = app.amplitude_platform