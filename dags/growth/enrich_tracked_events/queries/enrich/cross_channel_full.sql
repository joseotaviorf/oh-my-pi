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
        event_type_sanitized AS event_name,
        CASE 
            WHEN event_type_sanitized NOT IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'offer_submitted_new',
                'sale_offer_form_accepted')
                THEN COALESCE(platform,amplitude_platform,'')
        END AS attribution_app_type,
        CASE 
            WHEN event_type_sanitized IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'offer_submitted_new',
                'sale_offer_form_accepted')
                THEN COALESCE(platform,amplitude_platform)
        END AS attribution_app_type_conversion,
        CASE 
            WHEN event_type_sanitized NOT IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'offer_submitted_new',
                'sale_offer_form_accepted')
                THEN COALESCE(branded,'')
        END AS attribution_branded,
        CASE 
            WHEN event_type_sanitized IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'offer_submitted_new',
                'sale_offer_form_accepted')
                THEN branded
        END AS attribution_branded_conversion,
        CASE 
            WHEN event_type_sanitized NOT IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'offer_submitted_new',
                'sale_offer_form_accepted')
                THEN (
                    CASE
                        WHEN ts_app_attribution > ts_web_attribution THEN 'App'
                        ELSE 'Web'
                    END
                )
        END AS attribution_origin,
        CASE 
            WHEN event_type_sanitized IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'offer_submitted_new',
                'sale_offer_form_accepted')
                THEN (
                    CASE
                        WHEN ts_app_attribution > ts_web_attribution THEN 'App'
                        ELSE 'Web'
                    END
                )
        END AS attribution_origin_conversion,
        CASE 
            WHEN event_type_sanitized NOT IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'offer_submitted_new',
                'sale_offer_form_accepted')
                THEN COALESCE(utm_source,'')
        END AS attribution_source,
        CASE 
            WHEN event_type_sanitized IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'offer_submitted_new',
                'sale_offer_form_accepted')
                THEN utm_source
        END AS attribution_source_conversion,
        CASE 
            WHEN event_type_sanitized NOT IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'offer_submitted_new',
                'sale_offer_form_accepted')
                THEN COALESCE(utm_medium,'')
        END AS attribution_medium,
        CASE 
            WHEN event_type_sanitized IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'offer_submitted_new',
                'sale_offer_form_accepted')
                THEN utm_medium
        END AS attribution_medium_conversion,
        CASE 
            WHEN event_type_sanitized NOT IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'offer_submitted_new',
                'sale_offer_form_accepted')
                THEN COALESCE(utm_campaign,'')
        END AS attribution_campaign,
        CASE 
            WHEN event_type_sanitized IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'offer_submitted_new',
                'sale_offer_form_accepted')
                THEN utm_campaign
        END AS attribution_campaign_conversion,
        CASE 
            WHEN event_type_sanitized NOT IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'offer_submitted_new',
                'sale_offer_form_accepted')
                THEN COALESCE(utm_term,'')
        END AS attribution_term,
        CASE 
            WHEN event_type_sanitized IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'offer_submitted_new',
                'sale_offer_form_accepted')
                THEN utm_term
        END AS attribution_term_conversion,
        CASE 
            WHEN event_type_sanitized NOT IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'offer_submitted_new',
                'sale_offer_form_accepted')
                THEN COALESCE(utm_content,'')
        END AS attribution_content,
        CASE 
            WHEN event_type_sanitized IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'offer_submitted_new',
                'sale_offer_form_accepted')
                THEN utm_content
        END AS attribution_content_conversion,
        CASE 
            WHEN event_type_sanitized NOT IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'offer_submitted_new',
                'sale_offer_form_accepted')
                THEN COALESCE(media_source,'')
        END AS attribution_media_source,
        CASE 
            WHEN event_type_sanitized IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'offer_submitted_new',
                'sale_offer_form_accepted')
                THEN media_source
        END AS attribution_media_source_conversion,
        CASE 
            WHEN event_type_sanitized NOT IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'offer_submitted_new',
                'sale_offer_form_accepted')
                THEN entrance_uri
        END AS attribution_entrance_uri,
        CASE 
            WHEN event_type_sanitized IN (
                'visit_schedule_confirmed',
                'debug_visit_schedule_confirmed',
                'offer_submitted',
                'offer_submitted_new',
                'sale_offer_form_accepted')
                THEN entrance_uri
        END AS attribution_entrance_uri_conversion,
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
                'offer_submitted_new',
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
        event_name,
        'offline_table' AS attribution_app_type,
        'offline_table' AS attribution_app_type_conversion,
        CASE 
            WHEN origin IN (
                'Quinto Andar Classificados Lite',
                'Quinto Andar Classificados Hub',
                'Quinto Andar Inbound',
                'Quinto Andar Classificados Inbound',
                'CLASSIFIED', 
                'TQC_5A', 
                'INBOUND')  
                THEN 'Outro'
            WHEN origin IN (
                'Quinto Andar - Traz quem compra',
                'Quinto Andar - Placas', 
                'SIGN') 
                THEN 'Branded' 
            ELSE ''
        END AS attribution_branded,
        'offline_table' AS attribution_branded_conversion,
        COALESCE(agent,'') AS attribution_origin,
        'offline_table' AS attribution_origin_conversion,
        COALESCE(origin,'') AS attribution_source,
        'offline_table' AS attribution_source_conversion,
        COALESCE(channel,'') AS attribution_medium,
        'offline_table' AS attribution_medium_conversion,
        'offline_table' AS attribution_campaign,
        'offline_table' AS attribution_campaign_conversion,
        'offline_table' AS attribution_term,
        'offline_table' AS attribution_term_conversion,
        'offline_table' AS attribution_content,
        'offline_table' AS attribution_content_conversion,
        'offline_table' AS attribution_media_source,
        'offline_table' AS attribution_media_source_conversion,
        'offline_table' AS attribution_entrance_uri,
        'offline_table' AS attribution_entrance_uri_conversion,
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
            'Quinto Andar - Placas',
            'Placas',
            'CLASSIFIED', 
            'TQC_5A', 
            'SIGN', 
            'INBOUND'
            )
),
apply_attribution_rule AS (
    /*
    Get the attribution of the event immediately preceding the conversion event.
    The coalesces in the previous cte ensure that even making the field-by-field attribution assignment, 
    non-existent combinations are not generated
    */
    SELECT
        id_user,
        id_amplitude,
        id_session,
        id_house,
        id_firestore,
        id_contact,
        visit_code,
        event_name,
        LAST(attribution_app_type, TRUE) OVER(
            PARTITION BY id_user_conversion 
            ORDER BY ts_event ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS final_attribution_app_type,
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
        LAST(attribution_entrance_uri, TRUE) OVER(
            PARTITION BY id_user_conversion 
            ORDER BY ts_event ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS final_attribution_entrance_uri,    
        attribution_app_type_conversion,
        attribution_branded_conversion,
        attribution_origin_conversion,
        attribution_source_conversion,
        attribution_medium_conversion,
        attribution_campaign_conversion,
        attribution_term_conversion,
        attribution_content_conversion,
        attribution_media_source_conversion,
        attribution_entrance_uri_conversion,
        ts_event,
        year,
        month,
        day
    FROM
        cross_channel
)
/*
Once it gets events from distinct sources, it is necessary to order them 
to verify the last change attribution touchpoint event before the conversion event.
Some of these events may not be carrying utms (by failure or something else). 
For that reason, when it happens it's applied a rule to get the utm from the conversion event.

So if there is no event immediately preceding the conversion event
or the source and medium are empty (not expected), get the attribution of the conversion event
*/
SELECT
    id_user,
    id_amplitude,
    id_session,
    id_house,
    id_firestore,
    id_contact,
    visit_code,
    event_name,
    CASE
        WHEN 
            NULLIF(final_attribution_app_type, '') IS NULL
            OR (NULLIF(final_attribution_source, '') IS NULL
            AND NULLIF(final_attribution_medium, '') IS NULL) THEN attribution_app_type_conversion
        ELSE final_attribution_app_type
    END AS final_attribution_app_type,
    CASE
        WHEN NULLIF(final_attribution_app_type, '') IS NULL
            OR (NULLIF(final_attribution_source, '') IS NULL
            AND NULLIF(final_attribution_medium, '') IS NULL) THEN attribution_branded_conversion
        ELSE final_attribution_branded
    END AS final_attribution_branded,
    CASE
        WHEN NULLIF(final_attribution_app_type, '') IS NULL
            OR (NULLIF(final_attribution_source, '') IS NULL
            AND NULLIF(final_attribution_medium, '') IS NULL) THEN attribution_origin_conversion
        ELSE final_attribution_origin
    END AS final_attribution_origin,
    CASE
        WHEN NULLIF(final_attribution_app_type, '') IS NULL
            OR (NULLIF(final_attribution_source, '') IS NULL
            AND NULLIF(final_attribution_medium, '') IS NULL) THEN attribution_source_conversion
        ELSE final_attribution_source
    END AS final_attribution_source,
    CASE
        WHEN NULLIF(final_attribution_app_type, '') IS NULL
            OR (NULLIF(final_attribution_source, '') IS NULL
            AND NULLIF(final_attribution_medium, '') IS NULL) THEN attribution_medium_conversion
        ELSE final_attribution_medium
    END AS final_attribution_medium,
    CASE
        WHEN NULLIF(final_attribution_app_type, '') IS NULL
            OR (NULLIF(final_attribution_source, '') IS NULL
            AND NULLIF(final_attribution_medium, '') IS NULL) THEN attribution_campaign_conversion
        ELSE final_attribution_campaign
    END AS final_attribution_campaign,
    CASE
        WHEN NULLIF(final_attribution_app_type, '') IS NULL
            OR (NULLIF(final_attribution_source, '') IS NULL
            AND NULLIF(final_attribution_medium, '') IS NULL) THEN attribution_term_conversion
        ELSE final_attribution_term
    END AS final_attribution_term,
    CASE
        WHEN NULLIF(final_attribution_app_type, '') IS NULL
            OR (NULLIF(final_attribution_source, '') IS NULL
            AND NULLIF(final_attribution_medium, '') IS NULL) THEN attribution_content_conversion
        ELSE final_attribution_content
    END AS final_attribution_content,
    CASE
        WHEN NULLIF(final_attribution_app_type, '') IS NULL
            OR (NULLIF(final_attribution_source, '') IS NULL
            AND NULLIF(final_attribution_medium, '') IS NULL) THEN attribution_media_source_conversion
        ELSE final_attribution_media_source
    END AS final_attribution_media_source,
    CASE
        WHEN NULLIF(final_attribution_app_type, '') IS NULL
            OR (NULLIF(final_attribution_source, '') IS NULL
            AND NULLIF(final_attribution_medium, '') IS NULL) THEN attribution_entrance_uri_conversion
        ELSE final_attribution_entrance_uri
    END AS final_attribution_entrance_uri,
    ts_event,
    year,
    month,
    day
FROM
    apply_attribution_rule