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
    WHERE MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')

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
    WHERE MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
)

, prospect_activation_events AS (
    SELECT
        sk_prospect,
        sk_house,
        CASE
            WHEN event_name = 'USER FIRST ACTIVATION' THEN 'new_prospect'
            WHEN event_name IN ('USER RECOVERY', 'USER RECOVERY IN OTHER CITY GROUP') THEN 'recovered_prospect'
        END AS prospect_event_type,
        ts_event AS ts_prospect_event,
        sk_visit AS id_visit,
        operation_channel,
        UPPER(business_context) AS business_context
    FROM dw_growth.fact_demand_prospect_events
    WHERE event_name IN (
            'USER FIRST ACTIVATION',
            'USER RECOVERY',
            'USER RECOVERY IN OTHER CITY GROUP'
        )
        AND flow_order = 1
        AND ts_event BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
)

, messages_in_window AS (
  SELECT
    id_user,
    id_copilot_session,
    id_langfuse_session,
    id_notification,
    id_phone_session,
    user_phone,
    concierge_flow,
    concierge_flow_type,
    has_human_reply,
    has_audio,
    n_human_replies,
    n_audio_replies,
    ts_first_outbound_contact,
    ts_first_inbound_contact,
    ts_first_concierge_contact,
    ts_concierge_contact,
    year,
    month,
    day
  FROM datalake_search.concierge_messages
  WHERE MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
)

, phone2user AS (
  SELECT DISTINCT
    cr.id_reference AS id_user,
    ci.contact_info AS phone
  FROM datalake_person_clean.credential_reference cr
  JOIN datalake_person_clean.contact_info ci
    ON ci.id_person = cr.id_person
  WHERE ci.category = 'PHONE'
    AND ci.priority = 'PRIMARY'
    AND cr.origin = 'main'
    AND ci.contact_info IN (
      SELECT DISTINCT user_phone
      FROM messages_in_window
    )
)

, concierge_demand_ranked AS (
SELECT
    COALESCE(
        NULLIF(NULLIF(m.id_user, 0), -1),
        v.id_user,
        p2u.id_user,
        -1
    ) AS id_user,
    m.id_user AS id_user_copilot,
    v.id_user AS id_user_visit,
    m.id_copilot_session,
    m.id_langfuse_session,
    COALESCE(m.id_notification, CAST(-1 AS BIGINT)) AS id_notification,
    COALESCE(m.id_phone_session, '-') AS id_phone_session,
    v.id_house AS id_house_of_vb,
    v.id_visit,
    m.user_phone,
    COALESCE(v.visit_code, '-') AS visit_code,
    COALESCE(m.concierge_flow, 'Unknown') AS concierge_flow,
    COALESCE(m.concierge_flow_type, 'Unknown') AS concierge_flow_type,
    m.has_human_reply,
    m.has_audio,
    m.n_human_replies,
    m.n_audio_replies,
    COALESCE(pe.operation_channel, p.prospect_activation_channel) AS prospect_activation_channel,
    COALESCE(pe.prospect_event_type, p.prospect_event_type) AS prospect_event_type,
    m.user_phone IS NOT NULL
        AND (
            p.id_user IS NULL
            OR p.prospect_event_type = 'prospect_churn'
            OR (p.prospect_event_type <> 'prospect_churn' AND DATE(p.ts_prospect_event) = DATE(m.ts_concierge_contact))
        )
    AS is_contact_prospect,  -- a user is a contact prospect if he/she had contact with concierge and had never initiated a RENT/SALE flow, or had previously churned or had initiated a RENT/SALE flow on the day of the concierge contact.
    pe.sk_prospect IS NOT NULL AS is_concierge_prospect,
    COALESCE(v.business_context, p.business_context) AS business_context,
    p.business_context AS previous_prospect_business_context,
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
    COALESCE(m.ts_concierge_contact, TIMESTAMP('1970-01-01')) AS ts_concierge_contact,
    COALESCE(pe.ts_prospect_event, p.ts_prospect_event) AS ts_prospect_event,
    COALESCE(v.ts_concierge_visit_event, TIMESTAMP('1970-01-01')) AS ts_concierge_visit_event,
    v.ts_visit_created,
    COALESCE(m.year, v.year) AS year,
    COALESCE(m.month, v.month) AS month,
    COALESCE(m.day, v.day) AS day,
    ROW_NUMBER() OVER (
        PARTITION BY
            COALESCE(m.id_notification, CAST(-1 AS BIGINT)),
            COALESCE(m.id_phone_session, '-'),
            COALESCE(v.visit_code, '-'),
            COALESCE(m.concierge_flow_type, 'Unknown'),
            COALESCE(m.ts_concierge_contact, TIMESTAMP('1970-01-01')),
            COALESCE(v.ts_concierge_visit_event, TIMESTAMP('1970-01-01'))
        ORDER BY
            COALESCE(pe.ts_prospect_event, p.ts_prospect_event) DESC NULLS LAST,
            v.id_visit DESC NULLS LAST,
            pe.sk_prospect DESC NULLS LAST
    ) AS _row_num
FROM messages_in_window m
FULL JOIN visits v
    ON m.id_phone_session = v.id_phone_session
    AND m.ts_concierge_contact = v.ts_concierge_contact
    AND m.concierge_flow_type = v.concierge_flow_type
LEFT JOIN phone2user p2u
    ON m.user_phone = p2u.phone
    AND NULLIF(NULLIF(m.id_user, 0), -1) IS NULL
    AND v.id_user IS NULL
LEFT JOIN datalake_search.concierge_prospects_aux p
    ON COALESCE(NULLIF(NULLIF(m.id_user, 0), -1), v.id_user, p2u.id_user) = p.id_user
    AND m.ts_concierge_contact = p.ts_concierge_contact
    AND m.id_phone_session = p.id_phone_session
LEFT JOIN prospect_activation_events pe -- joining the visits that activated users as prospects with visits from concierge to get concierge prospects. The visits from concierge are the ones scheduled through concierge (direct) or through a visit schedule page link recommended by concierge on the same day as the contact (indirect).
    ON v.id_visit = pe.id_visit
    AND v.business_context = pe.business_context
    AND (v.visit_event_type = 'VISIT_SCHEDULED' OR v.days_msg2vb = 0)
WHERE MAKE_DATE(m.year, m.month, m.day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
    OR MAKE_DATE(v.year, v.month, v.day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
)

SELECT
    id_user,
    id_user_copilot,
    id_user_visit,
    id_copilot_session,
    id_langfuse_session,
    id_notification,
    id_phone_session,
    id_house_of_vb,
    id_visit,
    user_phone,
    visit_code,
    concierge_flow,
    concierge_flow_type,
    has_human_reply,
    has_audio,
    n_human_replies,
    n_audio_replies,
    prospect_activation_channel,
    prospect_event_type,
    is_contact_prospect,
    is_concierge_prospect,
    business_context,
    previous_prospect_business_context,
    concierge_vb_type,
    visit_request_channel,
    concierge_visit_event,
    is_visit_booked,
    is_visit_completed,
    is_offer_submitted,
    is_offer_accepted,
    is_contract_signed,
    days_msg2indirect_vb,
    ts_first_outbound_contact,
    ts_first_inbound_contact,
    ts_first_concierge_contact,
    ts_concierge_contact,
    ts_prospect_event,
    ts_concierge_visit_event,
    ts_visit_created,
    year,
    month,
    day
FROM concierge_demand_ranked
WHERE _row_num = 1
