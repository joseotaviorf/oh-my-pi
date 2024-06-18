WITH
attribution_cross_channel AS (
    SELECT
        *,
        -- Consider visit_schedule_confirmed over debug_visit_schedule_confirmed if they have the same visit_code
        ROW_NUMBER() OVER(PARTITION BY COALESCE(visit_code,id_firestore) ORDER BY event_name DESC,ts_event) AS attribution_rn
    FROM
        datalake_tracked_events.cross_channel_full
    WHERE
        event_name IN (
            'visit_schedule_confirmed',
            'debug_visit_schedule_confirmed',
            'offer_submitted',
            'sale_offer_form_accepted'
        )
)
SELECT
    id_user,
    id_amplitude,
    id_session,
    id_house,
    id_firestore,
    id_contact,
    visit_code,
    event_name,
    final_attribution_app_type,
    final_attribution_branded,
    COALESCE(final_attribution_origin,'cross_channel_attribution') AS final_attribution_origin,
    final_attribution_source,
    final_attribution_medium,
    final_attribution_campaign,
    final_attribution_term,
    final_attribution_content,
    final_attribution_media_source,
    final_attribution_entrance_uri,
    ts_event,
    year,
    month,
    day
FROM
    attribution_cross_channel
WHERE
    attribution_rn = 1