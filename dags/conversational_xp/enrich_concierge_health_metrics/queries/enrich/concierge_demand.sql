SELECT DISTINCT
    COALESCE(m.id_user, d.id_user, i.id_user) AS id_user,
    m.id_copilot_session,
    m.user_phone,
    m.id_phone_session,
    COALESCE(d.id_house, i.id_house) AS id_house_of_vb,
    COALESCE(d.id_visit, i.id_visit) AS id_visit,
    COALESCE(d.visit_code, i.visit_code) AS visit_code,
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
        AND (
            COALESCE(d.is_direct_visit_booked, FALSE) 
            OR COALESCE(i.is_indirect_visit_booked, FALSE) 
        )
    AS is_concierge_prospect, -- Users who became a prospect by initiating a RENT/SALE flow by booking a visit through concierge (direct or indirect).
    COALESCE(d.business_context, i.business_context, p.business_context) AS business_context,
    CASE
        WHEN d.is_direct_visit_booked THEN 'direct'
        WHEN i.is_indirect_visit_booked THEN 'indirect'
        ELSE 'no booking'
    END AS concierge_vb_type,
    COALESCE(d.visit_request_channel, i.visit_request_channel) AS visit_request_channel,
    d.visit_event_type AS concierge_visit_event,
    COALESCE(d.is_direct_visit_booked, i.is_indirect_visit_booked) AS is_visit_booked,
    COALESCE(d.is_visit_completed, i.is_visit_completed) AS is_visit_completed,
    COALESCE(d.is_offer_submitted, i.is_offer_submitted) AS is_offer_submitted,
    COALESCE(d.is_offer_accepted, i.is_offer_accepted) AS is_offer_accepted,
    COALESCE(d.is_contract_signed, i.is_contract_signed) AS is_contract_signed,
    i.days_msg2vb AS days_msg2indirect_vb,
    m.ts_first_outbound_contact,
    m.ts_first_inbound_contact,
    m.ts_first_concierge_contact,
    m.ts_concierge_contact,
    p.ts_prospect_event,
    d.ts_visit_event_created AS ts_concierge_visit_event,
    COALESCE(d.ts_visit_created, i.ts_visit_created) AS ts_visit_created,
    COALESCE(m.year, YEAR(d.ts_visit_created), YEAR(i.ts_visit_created)) AS year,
    COALESCE(m.month, MONTH(d.ts_visit_created), MONTH(i.ts_visit_created)) AS month,
    COALESCE(m.day, DAY(d.ts_visit_created), DAY(i.ts_visit_created)) AS day
FROM datalake_search.concierge_messages m
LEFT JOIN datalake_search.concierge_prospects_aux p
    ON m.id_user = p.id_user
    AND m.ts_concierge_contact = p.ts_concierge_contact
FULL JOIN datalake_search.concierge_direct_vb d
    ON m.id_phone_session = d.id_phone_session
    AND m.ts_message_sent = d.ts_message_sent
    AND m.concierge_flow_type = d.concierge_flow_type
FULL JOIN datalake_search.concierge_indirect_vb i
    ON m.id_phone_session = i.id_phone_session
    AND m.ts_message_sent = i.ts_message_sent
    AND m.concierge_flow_type = i.concierge_flow_type
WHERE COALESCE(MAKE_DATE(m.year, m.month, m.day), MAKE_DATE(d.year, d.month, d.day), MAKE_DATE(i.year, i.month, i.day)) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_7}) AND DATE('{end_date}')