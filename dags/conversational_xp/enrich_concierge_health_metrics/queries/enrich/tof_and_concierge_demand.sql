WITH tof_aux AS (
    SELECT DISTINCT 
        id_user,
        id_amplitude
    FROM datalake_search.amplitude_user_device
)

, tof_users AS (
    SELECT DISTINCT 
        COALESCE(t.id_user, ta.id_user) AS id_user,
        t.id_amplitude,
        UPPER(t.business_context) AS business_context,
        DATE(t.ts_event) AS dt_tof_event
    FROM datalake_amplitude_page_viewed_events.schedule_search_listing_events t
    LEFT JOIN tof_aux ta
        ON t.id_amplitude = ta.id_amplitude
    WHERE DATE(t.ts_event) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_60}) AND DATE('{end_date}')
)

SELECT DISTINCT 
    COALESCE(c.id_user, t.id_user) AS id_user,
    t.id_amplitude,
    c.id_copilot_session,
    c.user_phone,
    c.id_phone_session,
    c.id_house_of_vb,
    c.id_visit,
    c.visit_code,
    c.concierge_flow,
    c.concierge_flow_type,
    c.has_human_reply,
    c.has_audio,
    c.n_human_replies,
    c.n_audio_replies,
    c.prospect_activation_channel,
    c.prospect_event_type,
    c.is_contact_prospect,
    c.is_concierge_prospect, 
    COALESCE(c.business_context, bc.business_context, t.business_context) AS business_context,
    c.concierge_vb_type,
    c.visit_request_channel,
    c.concierge_visit_event,
    c.is_visit_booked,
    c.is_visit_completed,
    c.is_offer_submitted,
    c.is_offer_accepted,
    c.is_contract_signed,
    c.days_msg2indirect_vb,
    c.ts_first_outbound_contact,
    c.ts_first_inbound_contact,
    c.ts_first_concierge_contact,
    c.ts_concierge_contact,
    c.ts_prospect_event,
    c.ts_concierge_visit_event,
    c.ts_visit_created,
    t.dt_tof_event,
    COALESCE(t.dt_tof_event, MAKE_DATE(c.year, c.month, c.day)) AS dt_tof_or_concierge,
    COALESCE(c.year, YEAR(t.dt_tof_event)) AS year,
    COALESCE(c.month, MONTH(t.dt_tof_event)) AS month,
    COALESCE(c.day, DAY(t.dt_tof_event)) AS day
FROM tof_users AS t
FULL JOIN datalake_search.concierge_demand c
    ON t.id_user = c.id_user 
    AND t.dt_tof_event = MAKE_DATE(c.year, c.month, c.day)
LEFT JOIN tof_users AS bc -- Concierge messages lack native business context, thus we are inferring it from previous 30-day Top-of-Funnel (ToF) events. Note that business context within the concierge_demand table is currently derived from booked visits through concierge or prospect events, which accounts for a small proportion of total records.
    ON c.id_user = bc.id_user 
    AND DATE_DIFF(MAKE_DATE(c.year, c.month, c.day), bc.dt_tof_event) <= 30
    AND bc.business_context IS NOT NULL
WHERE t.dt_tof_event BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
    OR MAKE_DATE(c.year, c.month, c.day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')