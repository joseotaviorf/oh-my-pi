WITH transfer_reason AS (
  SELECT DISTINCT
    id_reviewed AS id_reservation,
    rating_selected[0] AS transference_reason
  FROM
    datalake_insider_clean.review r
  JOIN
    datalake_insider_clean.review_feature rf
      ON r.id = rf.id_review
  JOIN
    datalake_insider_clean.feature f
      ON rf.id_feature = f.id
  WHERE
    f.name = 'ticket_transfer_reason'
    AND r.type = 'ticket_transfer'
    AND id_reviewed like 'WR%'
),
segment AS (
  SELECT
    r.id_call,
    COALESCE(r.id_call, r.id_task) AS sk_call,
    r.id_task,
    r.id_reservation,
    r.id_worker AS id_agent,
    r.id_queue,
    r.worker_email,
    r.queue_name,
    LAG(r.queue_name, 1) OVER (PARTITION BY r.id_task ORDER BY r.ts_created) AS transferred_from_dept,
    LEAD(r.queue_name, 1) OVER (PARTITION BY r.id_task ORDER BY r.ts_created) AS transferred_to_dept,
    CASE
      WHEN LEAD(r.queue_name, 1) OVER (PARTITION BY r.id_task ORDER BY r.ts_created) = queue_name
        AND LEAD(r.id_queue, 1) OVER (PARTITION BY r.id_task ORDER BY r.ts_created) = id_queue
        THEN 'internal-same-agent'
      WHEN LEAD(r.queue_name, 1) OVER (PARTITION BY r.id_task ORDER BY r.ts_created) = queue_name
        AND LEAD(r.id_queue, 1) OVER (PARTITION BY r.id_task ORDER BY r.ts_created) != id_queue
        THEN 'internal-other-agent'
      WHEN LEAD(r.queue_name, 1) OVER (PARTITION BY r.id_task ORDER BY r.ts_created) != queue_name
        THEN 'external'
    END AS transference_type,
    tr.transference_reason,
    CASE
        WHEN r.queue_name LIKE "%MX%" THEN "MX"
        ELSE "BR"
    END AS country_code,
    r.is_answered,
    r.ts_created,
    r.ts_ended,
    r.ts_created - INTERVAL 3 HOUR AS ts_twilio_created_local,
    r.ts_ended - INTERVAL 3 HOUR AS ts_twilio_closed_local
  FROM
    datalake_bigfone.reservations AS r
  LEFT JOIN
    transfer_reason tr
      ON tr.id_reservation = r.id_reservation
  WHERE
    is_answered = TRUE
),
ivr_events AS (
  SELECT
    id_call,
    from_phone_number AS from_number,
    to_phone_number AS to_number,
    (
      UNIX_TIMESTAMP(MAX(ts_created - INTERVAL 3 HOUR)) - UNIX_TIMESTAMP(MIN(ts_created - INTERVAL 3 HOUR))
    ) / 60 AS total_minutes_reception_time,
    MIN(id_task) AS id_task,
    MIN(ts_created - INTERVAL 3 HOUR) AS ts_first_event,
    MAX(ts_created - INTERVAL 3 HOUR) AS ts_last_event,
    MIN(UNIX_TIMESTAMP(ts_created - INTERVAL 3 HOUR)) AS ts_first_event_local_unix,
    MAX(UNIX_TIMESTAMP(ts_created - INTERVAL 3 HOUR)) AS ts_last_event_local_unix
  FROM
    datalake_bigfone.ivr_tasks
  GROUP BY 1, 2, 3
),
call_events AS (
  SELECT
    id_task,
    id_call,
    channel_type,
    from_phone_number AS from_number,
    to_phone_number AS to_number,
    direction,
    is_scheduled,
    MIN(ts_created - INTERVAL 3 HOUR) AS ts_first_event,
    MAX(ts_created - INTERVAL 3 HOUR) AS ts_last_event,
    MIN(UNIX_TIMESTAMP(ts_created - INTERVAL 3 HOUR)) AS ts_first_event_local_unix,
    MAX(UNIX_TIMESTAMP(ts_created - INTERVAL 3 HOUR)) AS ts_last_event_local_unix
  FROM
    datalake_bigfone_clean.event
  WHERE
    year >= 2023
    AND event_type != 'task.updated'
    AND (
      is_scheduled IS NULL
      OR is_scheduled IS FALSE
      OR (
        is_scheduled IS TRUE
        AND GET_JSON_OBJECT(metadata, '$.event_data.TaskAttributes.conversations.conversation_attribute_1') = 2
      )
    )
  GROUP BY 1, 2, 3, 4, 5, 6, 7
),
csat AS (
  SELECT DISTINCT
    id_call,
    id_task,
    csat_1,
    csat_2,
    ts_created - INTERVAL 3 HOUR AS ts_created_local,
    ROW_NUMBER() OVER (PARTITION BY id_call ORDER BY ts_created) AS rw_number_asc,
    ROW_NUMBER() OVER (PARTITION BY id_call ORDER BY ts_created DESC) AS rw_number_desc
  FROM
    datalake_bigfone_clean.event
  WHERE
    year >= 2023
    AND csat_2 IS NOT NULL
),
csat_events AS (
  SELECT
    ca.id_call,
    ca.id_task,
    ca.csat_2 AS last_csat_score,
    ca2.csat_2 AS first_csat_score,
    ca.ts_created_local AS ts_last_response,
    ca2.ts_created_local AS ts_first_response,
    ca.csat_1
  FROM
    csat AS ca
  INNER JOIN
    csat AS ca2
      ON ca2.id_call = ca.id_call
      AND ca2.rw_number_asc = 1
  WHERE
    ca.rw_number_desc = 1
),
call_metrics AS (
  SELECT
    id_task,
    COUNT(DISTINCT queue_name) AS number_of_departments,
    COUNT(DISTINCT id_reservation) AS number_of_tasks,
    SUM(CAST(is_answered AS SMALLINT)) AS reservations_accepted,
    MIN(ts_created) AS ts_first_reservation,
    MAX(ts_created) AS ts_last_reservation
  FROM
    datalake_bigfone.reservations
  WHERE
    is_answered IS TRUE
  GROUP BY 1
),
twilio_time_metrics AS (
  SELECT
    ctm.id_segment,
    CASE
      WHEN SUM(ctm.total_talk_time) IS NULL THEN 0
      ELSE CAST(SUM(ctm.total_talk_time) AS FLOAT)
    END AS total_talk_time,
    CASE
      WHEN SUM(ctm.total_queue_time) IS NULL THEN 0
      ELSE CAST(SUM(ctm.total_queue_time) AS FLOAT)
    END AS total_queue_time,
    CASE
      WHEN SUM(ctm.total_wrap_up_time) IS NULL THEN 0
      ELSE CAST(SUM(ctm.total_wrap_up_time) AS FLOAT)
    END AS total_wrap_up_time,
    CASE
      WHEN SUM(ctm.total_handling_time) IS NULL THEN 0
      ELSE CAST(SUM(ctm.total_handling_time) AS FLOAT)
    END AS total_handling_time
  FROM
    datalake_twilio_flex_insights_clean.conversation_time_metrics ctm
  GROUP BY 1
),
conversation AS (
  SELECT DISTINCT
    COALESCE(ie.id_call, fe.id_call) AS id_call,
    COALESCE(ie.id_call, fe.id_call, fe.id_task) AS sk_call,
    COALESCE(fe.id_task, ie.id_task) AS id_task,
    COALESCE(ie.from_number, fe.from_number) AS from_phone_number,
    COALESCE(ie.to_number, fe.to_number) AS to_phone_number,
    fe.direction,
    fe.channel_type,
    COALESCE(cm.number_of_tasks, 0) AS number_of_tasks,
    COALESCE(cm.number_of_departments, 0) AS number_of_departments,
    cm.number_of_tasks IS NULL OR cm.number_of_tasks = 0 AS has_ended_in_ura,
    cm.reservations_accepted > 0 AS is_answered,
    cm.number_of_tasks > 1 AS is_transfered,
    ctm.total_queue_time AS seconds_total_wait_time,
    ctm.total_talk_time AS seconds_total_talk_time,
    ctm.total_queue_time AS seconds_total_queue_time,
    ctm.total_wrap_up_time AS seconds_total_wrap_up_time,
    ctm.total_handling_time AS seconds_total_handling_time,
    COALESCE(
      CAST(ce.first_csat_score AS string),
      CAST(ce.csat_1 AS string)
    ) IS NOT NULL AS is_csat_answered,
    ce.csat_1 = 1 AS is_solved,
    ce.last_csat_score,
    ce.first_csat_score,
    ie.total_minutes_reception_time,
    (
      GREATEST(ie.ts_last_event_local_unix, fe.ts_last_event_local_unix)
      - COALESCE(ie.ts_first_event_local_unix,fe.ts_first_event_local_unix)
    ) AS seconds_duration,
    COALESCE(ie.ts_first_event, fe.ts_first_event) AS ts_started,
    ce.ts_first_response AS ts_csat_first_response,
    ce.ts_last_response AS ts_csat_last_response,
    GREATEST(ie.ts_last_event, fe.ts_last_event) AS ts_ended,
    fe.ts_first_event AS ts_created
  FROM
    ivr_events ie
  FULL JOIN
    call_events fe
      ON fe.id_call = ie.id_call
  LEFT JOIN
    csat_events ce
      ON ce.id_task = fe.id_task
      OR ce.id_call = fe.id_call
  LEFT JOIN
    call_metrics cm
      ON cm.id_task = fe.id_task
  LEFT JOIN
    twilio_time_metrics ctm
      ON fe.id_task = ctm.id_segment
),
zendesk_tickets_unique AS (
  --this CTE fix the error of multiple tickets openned for a single call
  SELECT
    id_call,
    MAX(id_ticket) AS id_ticket
  FROM
    datalake_zendesk.tickets_current
  WHERE
    id_call IS NOT NULL
  GROUP BY 1
),
zendesk_aditional_ticket_info AS (
  SELECT DISTINCT
    id_ticket,
    id_call,
    id_user_main AS id_user,
    id_contract,
    tags,
    description,
    status,
    TO_JSON(custom_fields) AS custom_fields,
    group_name AS zendesk_ticket_department,
    first_resolution_time_min_calendar AS minutes_first_resolution_time_calendar,
    first_resolution_time_min_business AS minutes_first_resolution_time_business,
    replies,
    reopens,
    request_type,
    client_type,
    step_tag,
    customer_type_tag,
    contact_motivation_tag,
    contact_theme_tag,
    contact_theme_detail_tag,
    ts_created - INTERVAL 3 HOUR AS ts_created,
    ts_solved - INTERVAL 3 HOUR AS ts_solved
  FROM
    datalake_zendesk.tickets_current
),
back_tickets AS (
  SELECT
    COALESCE(
      NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(zd.custom_fields, '$.Ticket do contato'), '(WT[a-z0-9]{{20,40}})', 1), ''),
      REGEXP_EXTRACT(zd.description, '(WT[a-z0-9]{{20,40}})', 1)
    ) AS front_task,
    zd.id_ticket AS back_ticket,
    zd.status,
    zd2.id_ticket AS front_ticket,
    zd.ts_created,
    zd.ts_solved
  FROM
    zendesk_aditional_ticket_info zd
  INNER JOIN
    conversation c
      ON c.id_task = COALESCE(
        NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(zd.custom_fields, '$.Ticket do contato'), '(WT[a-z0-9]{{20,40}})', 1), ''),
        REGEXP_EXTRACT(zd.description, '(WT[a-z0-9]{{20,40}})', 1)
      )
  LEFT JOIN
    datalake_gsheets_clean.department_control dc
      ON dc.department = zd.zendesk_ticket_department
  INNER JOIN
    zendesk_aditional_ticket_info zd2
      ON zd2.id_call = c.sk_call
  WHERE
    (zd.tags LIKE '%tarefa_atendimento_escalado%' OR LOWER(dc.front_or_back) = 'back')
    AND (zd.tags NOT LIKE '%bot_end_conversation%' AND zd.tags NOT LIKE '%closed_by_merge%')
    AND COALESCE(
      NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(zd.custom_fields, '$.Ticket do contato'), '(WT[a-z0-9]{{20,40}})', 1), ''),
      REGEXP_EXTRACT(zd.description, '(WT[a-z0-9]{{20,40}})', 1)
    ) != ''
  GROUP BY 1, 2, 3, 4, 5, 6
),
last_and_first_back_tickets_timestamps AS (
  SELECT
    front_ticket,
    CONCAT_WS(',' , COLLECT_SET(back_ticket)) AS back_ticket_list,
    SUM(CAST(status IN ('closed','deleted','solved') AS SMALLINT))/CAST(COUNT(DISTINCT back_ticket) AS FLOAT) != 1 AS is_open_back_ticket,
    MIN(ts_created) AS ts_first_created,
    MAX(ts_solved) AS ts_last_solved
  FROM
    back_tickets
  GROUP BY 1
),
last_back_ticket AS (
  SELECT
    bt.*,
    lt.is_open_back_ticket,
    lt.back_ticket_list,
    lt.ts_first_created,
    CAST((TO_UNIX_TIMESTAMP(lt.ts_last_solved) - TO_UNIX_TIMESTAMP(lt.ts_first_created))/60.0 AS DOUBLE) AS total_backoffice_minutes_time
  FROM
    back_tickets bt
  JOIN
    last_and_first_back_tickets_timestamps lt
      ON lt.front_ticket = bt.front_ticket
      AND lt.ts_last_solved = bt.ts_solved
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY bt.front_ticket ORDER BY lt.ts_first_created DESC) = 1
),
conversation_and_segment AS (
  SELECT
    c.id_task AS id_external_service,
    t.id_reservation,
    c.id_call,
    c.sk_call,
    t.id_agent,
    t.id_queue,
    FIRST(t.queue_name) OVER (PARTITION BY c.id_task ORDER BY t.ts_twilio_created_local ASC) AS first_department,
    FIRST(t.queue_name) OVER (PARTITION BY c.id_task ORDER BY t.ts_twilio_created_local DESC) AS last_department,
    t.worker_email AS agent_email,
    t.queue_name,
    t.transferred_from_dept,
    t.transferred_to_dept,
    t.transference_type,
    t.transference_reason,
    t.country_code,
    c.seconds_total_wait_time,
    c.total_minutes_reception_time,
    c.seconds_total_talk_time / 60.0 AS segment_minutes_duration,
    c.seconds_total_queue_time / 60.0 AS segment_minutes_wait_time,
    c.seconds_total_handling_time / 60.0 AS segment_minutes_talk_time,
    c.seconds_total_talk_time / 60.0 AS total_minutes_talk_time,
    c.seconds_total_queue_time / 60.0 AS total_minutes_queue_time,
    c.seconds_total_wrap_up_time / 60.0 AS total_minutes_wrap_up_time,
    c.seconds_total_handling_time / 60.0 AS total_minutes_handling_time,
    CAST(c.seconds_duration / 60.0 AS DOUBLE) AS minutes_full_resolution_time_calendar,
    CAST(c.number_of_departments AS INT) AS number_of_departments,
    CAST(c.number_of_tasks AS INT) AS number_of_segments,
    c.direction,
    c.channel_type,
    t.is_answered,
    c.has_ended_in_ura,
    CASE
      WHEN c.is_transfered = TRUE THEN TRUE
      ELSE FALSE
    END AS has_transfers,
    c.is_csat_answered,
    c.is_solved,
    c.first_csat_score,
    c.last_csat_score,
    c.ts_csat_first_response,
    c.ts_csat_last_response,
    t.ts_twilio_created_local,
    t.ts_twilio_closed_local,
    c.ts_started,
    c.ts_ended
  FROM
    conversation c
  INNER JOIN
    segment t
      ON t.id_task = c.id_task
),
call_inapp_sessions AS (
  SELECT
    ss.id AS id_session,
    bc.id_source_unique AS id_call
  FROM
    datalake_sauron_clean.session AS ss
  INNER JOIN
    datalake_bigfone_clean.call AS bc
      ON ss.source_identity = bc.id_source_unique
  WHERE
    ss.source_environment = "CallInApp"
)
SELECT DISTINCT
  zd.id_ticket,
  c.id_external_service,
  c.id_reservation AS id_segment,
  c.id_call,
  c.sk_call,
  cs.id_session,
  c.id_agent,
  c.id_queue,
  zd.id_user,
  zd.id_contract,
  FIRST(c.agent_email) OVER (PARTITION BY zd.id_ticket ORDER BY c.ts_twilio_created_local) AS first_agent_email,
  FIRST(c.agent_email) OVER (PARTITION BY zd.id_ticket ORDER BY c.ts_twilio_created_local DESC) AS last_agent_email,
  CASE
    WHEN c.channel_type = "call-in-app" OR c.direction = "outbound-api" THEN "call inapp"
    ELSE CONCAT("call ", direction)
  END AS ticket_origin,
  c.agent_email,
  c.queue_name AS department,
  zd.zendesk_ticket_department AS zendesk_department,
  c.first_department,
  c.last_department,
  c.transferred_from_dept,
  c.transferred_to_dept,
  c.transference_type,
  c.transference_reason,
  c.country_code,
  CASE
    WHEN c.seconds_total_wait_time <= 60 AND c.is_answered THEN TRUE
    WHEN c.seconds_total_wait_time > 60 AND c.is_answered THEN FALSE
    ELSE NULL
  END AS sla_achieved,
  c.total_minutes_reception_time,
  ROUND(c.segment_minutes_duration, 1) AS segment_minutes_duration,
  ROUND(c.segment_minutes_wait_time, 1) AS segment_minutes_wait_time,
  ROUND(c.segment_minutes_talk_time, 1) AS segment_minutes_talk_time,
  ROUND(c.total_minutes_talk_time, 1) AS total_minutes_talk_time,
  ROUND(c.total_minutes_queue_time, 1) AS total_minutes_queue_time,
  ROUND(c.total_minutes_wrap_up_time, 1) AS total_minutes_wrap_up_time,
  ROUND(c.total_minutes_handling_time, 1) AS total_minutes_handling_time,
  c.minutes_full_resolution_time_calendar,
  bt.total_backoffice_minutes_time,
  CAST((TO_UNIX_TIMESTAMP(bt.ts_first_created) - TO_UNIX_TIMESTAMP(c.ts_ended))/60.0 AS DOUBLE) AS total_minutes_front_to_open_back_ticket_time,
  c.number_of_departments,
  c.number_of_segments,
  c.direction,
  c.channel_type,
  zd.minutes_first_resolution_time_calendar,
  zd.minutes_first_resolution_time_business,
  zd.replies,
  zd.reopens,
  zd.request_type,
  zd.client_type,
  zd.step_tag,
  zd.customer_type_tag,
  zd.contact_motivation_tag,
  zd.contact_theme_tag,
  zd.contact_theme_detail_tag,
  zd.tags,
  zd.status,
  zd.custom_fields,
  dc.journey_step,
  dc.team,
  dc.area,
  FIRST(c.id_reservation) OVER (PARTITION BY zd.id_ticket ORDER BY c.ts_twilio_created_local DESC) = c.id_reservation AS is_last_segment,
  FIRST(c.id_reservation) OVER (PARTITION BY zd.id_ticket ORDER BY c.ts_twilio_created_local ASC) = c.id_reservation AS is_first_segment,
  bt.front_ticket IS NOT NULL AS has_back_tickets,
  zd.tags LIKE '%bot_end_conversation%' AS is_bot,
  zd.tags LIKE '%closed_by_merge%' AS is_closed_by_merge,
  CASE
    WHEN dc.front_or_back = 'Front' THEN 'front'
    WHEN dc.front_or_back = 'Back' OR zd.tags LIKE '%tarefa_atendimento_escalado%' THEN 'back'
    ELSE 'undefined'
  END AS front_or_back,
  c.has_ended_in_ura = FALSE AND c.is_answered = TRUE AS is_answered,
  bt.front_ticket IS NOT NULL AS has_back_ticket,
  bt.is_open_back_ticket,
  c.has_transfers,
  CAST((TO_UNIX_TIMESTAMP(COALESCE(bt.ts_solved, c.ts_ended)) - TO_UNIX_TIMESTAMP(c.ts_started))/60.0 AS DOUBLE) AS frt,
  bt.back_ticket AS last_back_ticket,
  bt.back_ticket_list,
  c.is_csat_answered,
  c.is_solved,
  ce.first_csat_score,
  ce.last_csat_score,
  ce.last_csat_score AS csat_rating,
  ce.ts_last_response AS ts_csat_answered,
  ce.ts_first_response AS ts_csat_first_response,
  ce.ts_last_response AS ts_csat_last_response,
  c.ts_twilio_created_local AS ts_segment_created,
  c.ts_twilio_closed_local AS ts_segment_closed,
  c.ts_started AS ts_ticket_started,
  c.ts_ended AS ts_ticket_ended
FROM
  conversation_and_segment c
LEFT JOIN
  call_inapp_sessions AS cs
    ON cs.id_call = c.sk_call
LEFT JOIN
  csat_events AS ce
    ON ce.id_call = c.id_call
INNER JOIN
  zendesk_aditional_ticket_info zd
      ON zd.id_call = c.sk_call
INNER JOIN
  zendesk_tickets_unique ztu
    ON zd.id_ticket = ztu.id_ticket
LEFT JOIN
  datalake_gsheets_clean.department_control dc
    ON dc.department = c.last_department
LEFT JOIN
  last_back_ticket bt
    ON bt.front_ticket = zd.id_ticket
