WITH visits AS (
    SELECT
        id_user,
        id_house,
        id_visit,
        id_phone_session,
        visit_code,
        concierge_flow_type,
        'direct' AS concierge_vb_type,
        visit_request_channel,
        visit_event_type,
        is_direct_visit_booked AS is_visit_booked,
        is_visit_completed,
        is_offer_submitted,
        is_offer_accepted, 
        is_contract_signed,
        business_context,
        NULL AS days_msg2vb,
        ts_concierge_contact,
        ts_visit_event_created AS ts_concierge_visit_event,
        ts_visit_created,
        year,
        month,
        day
    FROM datalake_search.concierge_direct_vb

    UNION ALL

    SELECT
        id_user,
        id_house,
        id_visit,
        id_phone_session,
        visit_code,
        concierge_flow_type,
        'indirect' AS concierge_vb_type,
        visit_request_channel,
        NULL AS visit_event_type,
        is_indirect_visit_booked AS is_visit_booked,
        is_visit_completed,
        is_offer_submitted,
        is_offer_accepted, 
        is_contract_signed,
        business_context,
        days_msg2vb,
        ts_concierge_contact,
        NULL AS ts_concierge_visit_event,
        ts_visit_created,
        year,
        month,
        day
    FROM datalake_search.concierge_indirect_vb
)

SELECT DISTINCT
    COALESCE(m.id_user, v.id_user) AS id_user,
    m.id_copilot_session,
    m.user_phone,
    m.id_phone_session,
    v.id_house AS id_house_of_vb,
    v.id_visit, 
    v.visit_code,
    COALESCE(m.concierge_flow, 'Unknown') AS concierge_flow,
    COALESCE(m.concierge_flow_type, 'Unknown') AS concierge_flow_type,
    m.has_human_reply,
    p.prospect_activation_channel,
    p.prospect_event_type,
    m.user_phone IS NOT NULL
        AND (
            p.id_user IS NULL 
            OR p.prospect_event_type = 'prospect_churn' 
            OR (p.prospect_event_type <> 'prospect_churn' AND DATE(p.ts_prospect_event) = DATE(m.ts_message_sent)) 
        )
    AS is_contact_prospect,  -- a user is a contact prospect if he/she had contact with concierge and had never initiated a RENT/SALE flow, or had previously churned or had initiated a RENT/SALE flow on the day of the concierge contact.
    m.user_phone IS NOT NULL
        AND (
            p.id_user IS NULL 
            OR p.prospect_event_type = 'prospect_churn' 
            OR (p.prospect_event_type <> 'prospect_churn' AND DATE(p.ts_prospect_event) = DATE(m.ts_message_sent))
        )
        AND COALESCE(v.is_visit_booked, FALSE)
    AS is_concierge_prospect, -- Users who became a prospect by initiating a RENT/SALE flow by booking a visit through concierge (direct or indirect).
    COALESCE(v.business_context, p.business_context) AS business_context,
    COALESCE(v.concierge_vb_type, 'no booking') AS concierge_vb_type,
    v.visit_request_channel,
    v.visit_event_type AS concierge_visit_event,
    v.is_visit_booked,
    v.is_visit_completed,
    v.is_offer_submitted,
    v.is_offer_accepted,
    v.is_contract_signed,
    v.days_msg2vb AS days_msg2indirect_vb,
    m.ts_first_outbound_contact,
    m.ts_first_inbound_contact,
    m.ts_first_concierge_contact,
    m.ts_concierge_contact,
    p.ts_prospect_event,
    v.ts_concierge_visit_event,
    v.ts_visit_created,
    COALESCE(m.year, v.year) AS year,
    COALESCE(m.month, v.month) AS month,
    COALESCE(m.day, v.day) AS day
FROM datalake_search.concierge_messages m
LEFT JOIN datalake_search.concierge_prospects_aux p
    ON m.id_user = p.id_user
    AND m.ts_concierge_contact = p.ts_concierge_contact
FULL JOIN visits v
    ON m.id_phone_session = v.id_phone_session
    AND m.ts_concierge_contact = v.ts_concierge_contact
    AND m.concierge_flow_type = v.concierge_flow_type
WHERE MAKE_DATE(m.year, m.month, m.day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_7}) AND DATE('{end_date}')
    OR MAKE_DATE(v.year, v.month, v.day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_7}) AND DATE('{end_date}')