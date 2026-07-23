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
    NOT fv.sk_funnel_offer_submitted IS NULL AS is_offer_submitted,
    NOT fv.sk_funnel_offer_accepted IS NULL AS is_offer_accepted,
    NOT fv.sk_funnel_contract_signed IS NULL AS is_contract_signed
  FROM datalake_amplitude_clean.170698_visit_schedule_confirmed_events AS a
  JOIN dw_visit.dim_visit AS dv
    ON dv.visit_code = a.ep_visit_code
  JOIN dw_visit.fact_visits AS fv
    ON dv.sk_visit = fv.sk_visit
  WHERE
    GET_JSON_OBJECT(event_properties, recset_showcase) = 'CONCIERGE_WHATSAPP'
    AND dv.dt_created BETWEEN DATE_ADD(CAST('{start_date}' AS DATE), STRUCT(days_past_30 AS days_past_30) * -1) AND CAST('{end_date}' AS DATE)
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
FROM (
  SELECT
    ivb.id_user,
    ivb.id_house,
    ivb.id_visit,
    c.id_phone_session,
    ivb.visit_code,
    COALESCE(c.concierge_flow_type, 'Unknown') AS concierge_flow_type,
    ivb.visit_request_channel,
    is_indirect_visit_booked,
    ivb.is_visit_completed,
    ivb.is_offer_submitted,
    ivb.is_offer_accepted,
    ivb.is_contract_signed,
    ivb.business_context,
    DATEDIFF(
      TO_DATE(CAST(ivb.ts_visit_created AS DATE)),
      TO_DATE(CAST(c.ts_message_sent AS DATE))
    ) AS days_msg2vb,
    c.ts_concierge_contact,
    c.ts_message_sent,
    ivb.ts_visit_created,
    YEAR(TO_DATE(ivb.ts_visit_created)) AS year,
    MONTH(TO_DATE(ivb.ts_visit_created)) AS month,
    DAY(TO_DATE(ivb.ts_visit_created)) AS day,
    ROW_NUMBER() OVER (PARTITION BY ivb.visit_code ORDER BY ivb.ts_visit_created - COALESCE(c.ts_message_sent, ivb.ts_visit_created) ASC) AS _w
  FROM concierge_indirect_vb AS ivb
  LEFT JOIN datalake_search.concierge_messages AS c
    ON ivb.id_user = c.id_user AND c.ts_message_sent <= ivb.ts_visit_created
) AS _t
WHERE
  _w = 1 /* If in the same message session there are many concierge_flow_types prior to the creation/change of the visit, it ties the visit to the last message. */