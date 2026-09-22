WITH recent_concierge_messages AS (
    SELECT
        id_phone_session,
        id_langfuse_session,
        concierge_flow_type,
        ts_concierge_contact,
        ts_message_sent
    FROM datalake_search.concierge_messages
    WHERE MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
),

langfuse_traces AS (
    SELECT
        id_trace,
        id_session
    FROM datalake_langfuse_clean.traces
    WHERE DATE(ts_created) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
),

langfuse_observations AS (
    SELECT
        id_trace,
        REGEXP_EXTRACT(GET_JSON_OBJECT(output, '$.answer'), 'Visit code ([A-Z0-9]+)', 1) AS visit_code
    FROM datalake_langfuse_clean.observations
    WHERE name IN ('schedule_visit_node', 'schedule_visit_v1', 'schedule_visit_v2')
        AND DATE(ts_started) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
),

request_logs AS (
    SELECT
        id_trace,
        visit_code
    FROM datalake_request_logging_clean.visits
    WHERE DATE(ts_request) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
),

concierge_direct_vb_code AS (
    -- This CTE retrieves the visit code from Langfuse traces that evoked schedule_visit_node, schedule_visit_v1, or schedule_visit_v2 (renamed 2026-08-25). These nodes confirm the schedule/reschedule of a visit. With introduction of app 1.5, visit_code is migrated to the request logging table.
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
),

direct_visits_ranked AS (
    -- This CTE gets all the schedules/reschedules of the visits through the concierge from the visit_status_events table. Then it joins to concierge_messages to map the visit to the type of concierge flow (inbound/outbound).
    -- If in the same message session there are many concierge_flow_types prior to the creation/change of the visit, rn = 1 ties the visit to the last message.
    SELECT
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
        DAY(vsl.ts_created) AS day,
        ROW_NUMBER() OVER (
            PARTITION BY dv.visit_code, vsl.ts_created
            ORDER BY vsl.ts_created - COALESCE(vc.ts_message_sent, vsl.ts_created) ASC
        ) AS rn
    FROM datalake_visit.visit_status_events AS vsl
    JOIN dw_visit.dim_visit AS dv
        ON dv.sk_visit = vsl.id_visit
    JOIN dw_visit.fact_visits AS fv
        ON dv.sk_visit = fv.sk_visit
    LEFT JOIN concierge_direct_vb_code AS vc
        ON vc.visit_code = dv.visit_code
        AND vc.ts_concierge_contact <= vsl.ts_created
        -- a message in concierge must precede a visit that was created/changed in whatsapp channel. This avoids joining the visit to later messages in the same session, as visit_code is tied to message session and not to message.
        AND vc.ts_message_sent <= vsl.ts_created
    WHERE vsl.channel IN ('CONVERSATIONAL - WHATSAPP_CONCIERGE', 'CONVERSATIONAL - NATIVE_CONCIERGE')
        AND vsl.event_type IN ('VISIT_SCHEDULED', 'VISIT_RESCHEDULED')
        AND DATE(vsl.ts_created) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
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
FROM direct_visits_ranked
WHERE rn = 1
