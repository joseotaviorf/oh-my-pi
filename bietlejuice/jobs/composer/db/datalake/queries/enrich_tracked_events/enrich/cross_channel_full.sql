WITH
cross_channel AS (
    -- ONLINE TOUCHPOINTS
    SELECT DISTINCT
        COALESCE(
            id_user, 
            id_amplitude,
            id_session
        ) AS id_user_conversion,
        id_user,
        id_amplitude,
        id_session,
        id_house,
        id_firestore,
        NULL AS id_contact,
        visit_code,
        COALESCE(platform,'') AS app_type,
        event_type_sanitized AS event_name,
        CASE 
            WHEN event_type_sanitized NOT IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'sale_offer_form_accepted')
                THEN COALESCE(branded,'')
        END AS attribution_branded,
        CASE 
            WHEN event_type_sanitized NOT IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'sale_offer_form_accepted')
                THEN (
                    CASE
                        WHEN ts_app_attribution > ts_web_attribution THEN 'App'
                        WHEN ts_web_attribution > ts_app_attribution THEN 'Web'
                        ELSE 'Web'
                    END
                )
        END AS attribution_origin,
        CASE 
            WHEN event_type_sanitized NOT IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'sale_offer_form_accepted')
                THEN COALESCE(utm_source,'')
        END AS attribution_source,
        CASE 
            WHEN event_type_sanitized NOT IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'sale_offer_form_accepted')
                THEN COALESCE(utm_medium,'')
        END AS attribution_medium,
        CASE 
            WHEN event_type_sanitized NOT IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'sale_offer_form_accepted')
                THEN COALESCE(utm_campaign,'')
        END AS attribution_campaign,
        CASE 
            WHEN event_type_sanitized NOT IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'sale_offer_form_accepted')
                THEN COALESCE(utm_term,'')
        END AS attribution_term,
        CASE 
            WHEN event_type_sanitized NOT IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'sale_offer_form_accepted')
                THEN COALESCE(utm_content,'')
        END AS attribution_content,
        CASE 
            WHEN event_type_sanitized NOT IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'sale_offer_form_accepted')
                THEN COALESCE(media_source,'')
        END AS attribution_media_source,
        ts_event,
        year,
        month,
        day
        FROM
            datalake_online_attribution.online_attribution
        WHERE
            ( -- FILTERING ONLY ATTRIBUTION CHANGE OR CONVERTION EVENTS
            ts_event = ts_web_attribution
            OR ts_event = ts_app_attribution
            OR event_type_sanitized IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'sale_offer_form_accepted')
            )
    UNION ALL
    -- OFFLINE TOUCHPOINTS
    SELECT
        COALESCE(
            id_user,
            id_contact
        ) AS id_user_conversion,
        id_user,
        NULL AS id_amplitude,
        NULL AS id_session,
        NULL AS id_house,
        NULL AS id_firestore,
        id_contact,
        NULL AS visit_code,
        'offline_table' AS app_type,
        event_name,
        CASE 
            WHEN origin IN (
                'Quinto Andar Classificados Lite',
                'Quinto Andar Classificados Hub',
                'Quinto Andar Inbound',
                'Quinto Andar Classificados Inbound') 
                THEN 'non-branded'
            WHEN origin IN (
                'Quinto Andar - Traz quem compra',
                'Quinto Andar - Placas') 
                THEN 'branded' 
            ELSE ''
        END AS attribution_branded,
        COALESCE(agent,'') AS attribution_origin,
        COALESCE(origin,'') AS attribution_source,
        COALESCE(channel,'') AS attribution_medium,
        'offline_table' AS attribution_campaign,
        'offline_table' AS attribution_term,
        'offline_table' AS attribution_content,
        'offline_table' AS attribution_media_source,
        ts_event,
        year,
        month,
        day
    FROM 
        datalake_tracked_events.offline_attribution
    WHERE 
        origin IN (
            'Quinto Andar Classificados Lite',
            'Quinto Andar Classificados Hub',
            'Quinto Andar Inbound',
            'Quinto Andar Classificados Inbound',
            'Quinto Andar - Traz quem compra',
            'Quinto Andar - Placas'
            )
)
/*
--- The coalesces in the previous cte ensure that even making the field-by-field attribution assignment, 
--- non-existent combinations are not generated
*/
SELECT
    id_user,
    id_amplitude,
    id_session,
    id_house,
    id_firestore,
    id_contact,
    visit_code,
    app_type,
    event_name,
    LAST(attribution_branded, TRUE) OVER(
        PARTITION BY id_user_conversion 
        ORDER BY ts_event ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS final_attribution_branded,
    LAST(attribution_origin, TRUE) OVER(
        PARTITION BY id_user_conversion 
        ORDER BY ts_event ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS final_attribution_origin,
    LAST(attribution_source, TRUE) OVER(
        PARTITION BY id_user_conversion 
        ORDER BY ts_event ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS final_attribution_source,
    LAST(attribution_medium, TRUE) OVER(
        PARTITION BY id_user_conversion 
        ORDER BY ts_event ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS final_attribution_medium,
    LAST(attribution_campaign, TRUE) OVER(
        PARTITION BY id_user_conversion 
        ORDER BY ts_event ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS final_attribution_campaign,
    LAST(attribution_term, TRUE) OVER(
        PARTITION BY id_user_conversion 
        ORDER BY ts_event ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS final_attribution_term,
    LAST(attribution_content, TRUE) OVER(
        PARTITION BY id_user_conversion 
        ORDER BY ts_event ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS final_attribution_content,
    LAST(attribution_media_source, TRUE) OVER(
        PARTITION BY id_user_conversion 
        ORDER BY ts_event ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS final_attribution_media_source,
    ts_event,
    year,
    month,
    day
FROM
    cross_channel