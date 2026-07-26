WITH recent_concierge_messages AS (
  SELECT
    id_phone_session,
    id_langfuse_session,
    concierge_flow_type,
    ts_concierge_contact,
    ts_message_sent
  FROM datalake_search.concierge_messages
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE_ADD(CAST('{start_date}' AS DATE), {days_past_30} * -1) AND CAST('{end_date}' AS DATE)
), langfuse_traces AS (
  SELECT
    id_trace,
    id_session
  FROM datalake_langfuse_clean.traces
  WHERE
    CAST(ts_created AS DATE) BETWEEN DATE_ADD(CAST('{start_date}' AS DATE), {days_past_30} * -1) AND CAST('{end_date}' AS DATE)
), langfuse_observations AS (
  SELECT
    id_trace,
    REGEXP_EXTRACT(GET_JSON_OBJECT(output, '$.answer'), 'Visit code ([A-Z0-9]+)') AS visit_code
  FROM datalake_langfuse_clean.observations
  WHERE
    name IN ('schedule_visit_node', 'schedule_visit_v1')
    AND CAST(ts_started AS DATE) BETWEEN DATE_ADD(CAST('{start_date}' AS DATE), {days_past_30} * -1) AND CAST('{end_date}' AS DATE)
), request_logs AS (
  SELECT
    id_trace,
    visit_code
  FROM datalake_request_logging_clean.visits
  WHERE
    CAST(ts_request AS DATE) BETWEEN DATE_ADD(CAST('{start_date}' AS DATE), {days_past_30} * -1) AND CAST('{end_date}' AS DATE)
), concierge_direct_vb_code AS (
  /* This CTE retrieves the visit code from the Langfuse traces (messages exchanged between user and concierge) that evoked schedule_visit_node. This node confirms the schedule/reschedule of a visit. With introduction of app 1.5, the visit_code are migrated to the request logging table. */
  SELECT DISTINCT
    c.id_phone_session,
    c.concierge_flow_type,
    c.ts_concierge_contact,
    c.ts_message_sent,
    COALESCE(v.visit_code, o.visit_code) AS visit_code
  FROM recent_concierge_messages AS c
  INNER JOIN langfuse_traces AS t
    ON c.id_langfuse_session = t.id_session
  INNER JOIN langfuse_observations AS o
    ON t.id_trace = o.id_trace
  LEFT JOIN request_logs AS v
    ON o.id_trace = v.id_trace
)
SELECT
  id_user,
  id_house,
  id_visit,
  id_phone_session,
  visit_code,
  concierge_flow_type,
  visit_request_channel,
  visit_event_type,
  is_direct_visit_booked,
  is_visit_completed,
  is_offer_submitted,
  is_offer_accepted,
  is_contract_signed,
  business_context,
  ts_concierge_contact,
  ts_message_sent,
  ts_visit_event_created,
  ts_visit_created,
  year,
  month,
  day
FROM (
  SELECT
    fv.sk_visitor AS id_user, /* This query gets all the schedules/reschedules of the visits through the concierge from the visit_status_events table. Then it joins to concierge_messages to map the visit to the type of concierge flow (inbound/outbound). */
    fv.sk_house AS id_house,
    dv.id_visit,
    vc.id_phone_session,
    dv.visit_code AS visit_code,
    COALESCE(vc.concierge_flow_type, 'Unknown') AS concierge_flow_type,
    dv.visit_request_channel,
    vsl.event_type AS visit_event_type,
    TRUE AS is_direct_visit_booked,
    dv.is_visit_completed,
    NOT fv.sk_funnel_offer_submitted IS NULL AS is_offer_submitted,
    NOT fv.sk_funnel_offer_accepted IS NULL AS is_offer_accepted,
    NOT fv.sk_funnel_contract_signed IS NULL AS is_contract_signed,
    dv.business_context,
    vc.ts_concierge_contact,
    vc.ts_message_sent,
    vsl.ts_created AS ts_visit_event_created,
    dv.dt_created AS ts_visit_created,
    YEAR(TO_DATE(vsl.ts_created)) AS year,
    MONTH(TO_DATE(vsl.ts_created)) AS month,
    DAY(TO_DATE(vsl.ts_created)) AS day,
    ROW_NUMBER() OVER (PARTITION BY dv.visit_code, vsl.ts_created ORDER BY vsl.ts_created - COALESCE(vc.ts_message_sent, vsl.ts_created) ASC) AS _w,
    vsl.ts_created
  FROM datalake_visit.visit_status_events AS vsl
  JOIN dw_visit.dim_visit AS dv
    ON dv.sk_visit = vsl.id_visit
  JOIN dw_visit.fact_visits AS fv
    ON dv.sk_visit = fv.sk_visit
  LEFT JOIN concierge_direct_vb_code AS vc
    ON vc.visit_code = dv.visit_code
    AND vc.ts_concierge_contact <= vsl.ts_created
    AND vc.ts_message_sent <= vsl.ts_created /* a message in concierge must preceed a visit that was created/changed in whatsapp channel. This avoids joining the visit to later messages in the same session, as visit_code is tied to message session and not to message. */
  WHERE
    vsl.channel IN ('CONVERSATIONAL - WHATSAPP_CONCIERGE', 'CONVERSATIONAL - NATIVE_CONCIERGE')
    AND vsl.event_type IN ('VISIT_SCHEDULED', 'VISIT_RESCHEDULED')
    AND vsl.ts_created BETWEEN DATE_ADD(CAST('{start_date}' AS DATE), {days_past_30} * -1) AND CAST('{end_date}' AS DATE)
) AS _t
WHERE
  _w = 1 /* If in the same message session there are many concierge_flow_types prior to the creation/change of the visit, it ties the visit to the last message. */
