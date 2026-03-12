WITH concierge_direct_vb_code AS (
    -- This CTE retrieves the visit code from the Langfuse traces (messages exchanged between user and concierge) that evoked schedule_visit_node. This node confirms the schedule/reschedule of a visit.    
    SELECT DISTINCT
        c.id_phone_session,
        c.concierge_flow_type,
        c.ts_concierge_contact,
        c.ts_message_sent,
        regexp_extract(get_json_object(o.output, '$.answer'), 'Visit code ([A-Z0-9]+)', 1) AS visit_code
    FROM datalake_search.concierge_messages AS c
    JOIN datalake_langfuse_clean.traces AS t
        ON c.id_langfuse_session = t.id_session
    JOIN datalake_langfuse_clean.observations AS o
        ON t.id_trace = o.id_trace
    WHERE o.name = 'schedule_visit_node'
        AND c.ts_concierge_contact BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_21}) AND DATE('{end_date}')
)

SELECT
    -- This query gets all the schedules/reschedules of the visits through the concierge from the visit_status_log table. Then it joins to concierge_messages to map the visit to the type of concierge flow (inbound/outbound).
    fv.sk_visitor AS id_user,
    fv.sk_house AS id_house,
    dv.id_visit,
    vc.id_phone_session,
    dv.visit_code AS visit_code,
    COALESCE(vc.concierge_flow_type, 'Unknown') AS concierge_flow_type,
    dv.visit_request_channel,
    vsl.event_type AS visit_event_type,
    TRUE AS is_direct_visit_booked,
    dv.is_visit_completed,
    fv.sk_funnel_offer_submitted IS NOT NULL AS is_offer_submitted,
    fv.sk_funnel_offer_accepted IS NOT NULL AS is_offer_accepted,
    fv.sk_funnel_contract_signed IS NOT NULL AS is_contract_signed,
    dv.business_context,
    vc.ts_concierge_contact,
    vc.ts_message_sent,
    vsl.ts_created AS ts_visit_event_created,
    dv.dt_created AS ts_visit_created,
    YEAR(vsl.ts_created) AS year,
    MONTH(vsl.ts_created) AS month,
    DAY(vsl.ts_created) AS day
FROM datalake_ebdb_clean.visit_status_log AS vsl
JOIN dw_visit.dim_visit AS dv
    ON dv.sk_visit = vsl.id_visit
JOIN dw_visit.fact_visits fv
    ON dv.sk_visit = fv.sk_visit
LEFT JOIN concierge_direct_vb_code AS vc
    ON vc.visit_code = dv.visit_code
    AND vc.ts_concierge_contact <= vsl.ts_created
    AND vc.ts_message_sent <= vsl.ts_created -- a message in concierge must preceed a visit that was created/changed in whatsapp channel. This avoids joining the visit to later messages in the same session, as visit_code is tied to message session and not to message.
WHERE vsl.channel = 'WHATSAPP_CONCIERGE'
    AND vsl.event_type IN ('VISIT_SCHEDULED', 'VISIT_RESCHEDULED')
    AND vsl.ts_created BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_21}) AND DATE('{end_date}')
QUALIFY ROW_NUMBER() OVER (PARTITION BY dv.visit_code, vsl.ts_created ORDER BY vsl.ts_created - COALESCE(vc.ts_message_sent, vsl.ts_created) ASC) = 1 -- If in the same message session there are many concierge_flow_types prior to the creation/change of the visit, it ties the visit to the last message.