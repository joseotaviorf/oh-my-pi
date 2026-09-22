WITH concierge_indirect_vb AS (
  SELECT DISTINCT
    a.id_user,
    a.ep_house_id AS id_house,
    dv.id_visit,
    a.ep_visit_code AS visit_code,
    dv.business_context,
    dv.visit_request_channel,
    dv.dt_created AS ts_visit_created,
    TRUE AS is_indirect_visit_booked,
    dv.is_visit_completed,
    fv.sk_funnel_offer_submitted IS NOT NULL AS is_offer_submitted,
    fv.sk_funnel_offer_accepted IS NOT NULL AS is_offer_accepted,
    fv.sk_funnel_contract_signed IS NOT NULL AS is_contract_signed
  FROM datalake_amplitude_clean.170698_visit_schedule_confirmed_events AS a
  JOIN dw_visit.dim_visit AS dv
    ON dv.visit_code = a.ep_visit_code
  JOIN dw_visit.fact_visits fv
    ON dv.sk_visit = fv.sk_visit
  WHERE get_json_object(event_properties, '$.recset_showcase') = 'CONCIERGE_WHATSAPP'
  AND DATE(dv.dt_created) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
)

, messages_in_window AS (
  SELECT
    id_user,
    id_phone_session,
    user_phone,
    concierge_flow_type,
    ts_concierge_contact,
    ts_message_sent
  FROM datalake_search.concierge_messages
  WHERE MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_120}) AND DATE('{end_date}')
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

, messages_resolved AS (
  SELECT
    c.id_phone_session,
    c.concierge_flow_type,
    c.ts_concierge_contact,
    c.ts_message_sent,
    COALESCE(NULLIF(NULLIF(c.id_user, 0), -1), p2u.id_user) AS id_user_resolved
  FROM messages_in_window c
  LEFT JOIN phone2user p2u
    ON c.user_phone = p2u.phone
    AND NULLIF(NULLIF(c.id_user, 0), -1) IS NULL
)

, indirect_vb_ranked AS (
  SELECT
    ivb.id_user,
    ivb.id_house,
    ivb.id_visit,
    c.id_phone_session,
    ivb.visit_code,
    COALESCE(c.concierge_flow_type, 'Unknown') AS concierge_flow_type,
    ivb.visit_request_channel,
    ivb.is_indirect_visit_booked,
    ivb.is_visit_completed,
    ivb.is_offer_submitted,
    ivb.is_offer_accepted,
    ivb.is_contract_signed,
    ivb.business_context,
    DATEDIFF(DATE(ivb.ts_visit_created), DATE(c.ts_message_sent)) AS days_msg2vb,
    c.ts_concierge_contact,
    c.ts_message_sent,
    ivb.ts_visit_created,
    YEAR(ivb.ts_visit_created) AS year,
    MONTH(ivb.ts_visit_created) AS month,
    DAY(ivb.ts_visit_created) AS day,
    -- Join only messages with ts_message_sent <= ts_visit_created so we never
    -- attribute a message sent after the booking. If several messages precede
    -- the visit, keep the last one.
    ROW_NUMBER() OVER (
      PARTITION BY ivb.visit_code
      ORDER BY c.ts_message_sent DESC NULLS LAST
    ) AS _row_num
  FROM concierge_indirect_vb ivb
  LEFT JOIN messages_resolved c
    ON ivb.id_user = c.id_user_resolved
    AND c.ts_message_sent <= ivb.ts_visit_created
)

SELECT
    id_user,
    id_house,
    id_visit,
    id_phone_session,
    visit_code,
    concierge_flow_type,
    visit_request_channel,
    is_indirect_visit_booked,
    is_visit_completed,
    is_offer_submitted,
    is_offer_accepted,
    is_contract_signed,
    business_context,
    days_msg2vb,
    ts_concierge_contact,
    ts_message_sent,
    ts_visit_created,
    year,
    month,
    day
FROM indirect_vb_ranked
WHERE _row_num = 1
