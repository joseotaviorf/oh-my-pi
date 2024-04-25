-- TO RUN ON DATABRICKS: replace double brackets ('{{', '}}') for single ones
WITH last_updated_task AS (
  SELECT
    *
  FROM
    datalake_quinto_messenger.task
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_task ORDER BY ts_updated DESC) = 1
),
task_outcome AS (
  SELECT
    id_task,
    task_completion_reason
  FROM
    datalake_quinto_messenger.task_event
  WHERE
    type = 'reservation.completed'
),
task_transfer_reason AS (
  SELECT DISTINCT
    id_reviewed AS id_task,
    rating_selected[0] AS transference_reason
  FROM
    datalake_insider_clean.review AS r
  INNER JOIN
    datalake_insider_clean.review_feature AS rf
      ON r.id = rf.id_review
  INNER JOIN
    datalake_insider_clean.feature AS f
      ON rf.id_feature = f.id
        AND f.name = 'ticket_transfer_reason'
),
task_timestamps AS (
  SELECT
    id_task,
    MAX(task_queue_name) AS department,
    MAX(ts_created_local) AS ts_task_closed,
    MIN(ts_created_local) AS ts_task_created
  FROM
    datalake_quinto_messenger.task_event
  WHERE
    type LIKE 'reservation.%'
  GROUP BY 1
),
whatsapp_metrics AS (
  SELECT
    id_conversation,
    COUNT(DISTINCT t.id_task) AS number_of_tasks,
    COUNT(DISTINCT te.task_queue_name) AS number_of_departments,
    MAX(te.ts_created_local) AS ts_last_event,
    MIN(te.ts_created_local) AS ts_first_event
  FROM
    datalake_quinto_messenger.task AS t
  INNER JOIN
    datalake_quinto_messenger.task_event AS te
      ON t.id_task = te.id_task
  GROUP BY 1
),
chat5a_metrics AS (
  SELECT
    c.id_session,
    COUNT(DISTINCT t.id_task) AS number_of_tasks,
    COUNT(DISTINCT te.task_queue_name) AS number_of_departments,
    MAX(te.ts_created_local) AS ts_last_event,
    MIN(te.ts_created_local) AS ts_first_event
  FROM
    datalake_quinto_messenger.task AS t
  INNER JOIN
    datalake_quinto_messenger.task_event AS te
      ON t.id_task = te.id_task
  INNER JOIN
    datalake_quinto_messenger.chat c
      ON c.id_chat = t.id_chat
  GROUP BY 1
),
task AS (
  SELECT
    t.id_task,
    t.id_channel,
    t.id_agent,
    t.id_chat,
    LOWER(t.agent_email) AS agent_email,
    tt.department,
    t.completion_reason,
    LAG(tt.department, 1) OVER (PARTITION BY t.id_channel ORDER BY tt.ts_task_created) AS transferred_from_dept,
    LEAD(tt.department, 1) OVER (PARTITION BY t.id_channel ORDER BY tt.ts_task_created) AS transferred_to_dept,
    CASE
        WHEN
          LEAD(tt.department, 1) OVER (PARTITION BY t.id_channel ORDER BY tt.ts_task_created) = tt.department
            AND LEAD(t.id_agent, 1) OVER (PARTITION BY t.id_channel ORDER BY tt.ts_task_created) = t.id_agent THEN 'internal-same-agent'
        WHEN
          LEAD(tt.department, 1) OVER (PARTITION BY t.id_channel ORDER BY tt.ts_task_created) = tt.department
            AND LEAD(t.id_agent, 1) OVER (PARTITION BY t.id_channel ORDER BY tt.ts_task_created) != t.id_agent THEN 'internal-other-agent'
        WHEN
          LEAD(tt.department, 1) OVER (PARTITION BY t.id_channel ORDER BY tt.ts_task_created) != tt.department THEN 'external'
    END AS transference_type,
    t.customer_type_tag,
    t.contact_motivation_tag,
    t.contact_theme_tag,
    t.seconds_to_first_response,
    tt.ts_task_closed,
    tt.ts_task_created,
    t.ts_created,
    t.ts_updated
  FROM
    last_updated_task AS t
  INNER JOIN
    task_timestamps AS tt
      ON tt.id_task = t.id_task
),
twilio_time_metrics AS (
  WITH task_metrics AS(
    SELECT DISTINCT
      ctm.id_segment AS id_task,
      lut.id_channel,
      ctm.total_talk_time,
      ctm.total_queue_time,
      ctm.total_wrap_up_time,
      ctm.total_handling_time
    FROM
      datalake_twilio_flex_insights_clean.conversation_time_metrics AS ctm
    INNER JOIN
      last_updated_task AS lut
        ON lut.id_task = ctm.id_segment
    WHERE
      total_talk_time IS NOT NULL
      AND total_queue_time IS NOT NULL
      AND total_wrap_up_time IS NOT NULL
      AND total_handling_time IS NOT NULL
  )
  SELECT
    id_channel,
    SUM(total_talk_time) AS total_talk_time,
    SUM(total_queue_time) AS total_queue_time,
    SUM(total_wrap_up_time) AS total_wrap_up_time,
    SUM(total_handling_time) AS total_handling_time
  FROM
    task_metrics
  GROUP BY 1
),
chatbot_time_metrics_whatsapp AS (
  SELECT
    s.id AS id_session,
    MIN(s.ts_created) AS ts_reception_started,
    (UNIX_TIMESTAMP(MIN(bot.ts_created)) - UNIX_TIMESTAMP(MIN(s.ts_created)))/60 AS total_minutes_reception_time
  FROM
    datalake_sauron_clean.bot_outgoing_messages AS bot
  INNER JOIN
    datalake_sauron_clean.session AS s
      ON s.id = bot.id_session
        AND GET_JSON_OBJECT(bot.bot_response, '$.action') = 'TRANSFER_CONVERSATION_TO_HUMAN'
  GROUP BY 1
),
chatbot_time_metrics_chat_inapp AS (
  WITH greenseer_sessions AS (
    SELECT
      id_session,
      ts_started
    FROM
      datalake_greenseer_clean.session
    QUALIFY
      ROW_NUMBER() OVER (PARTITION BY id_session ORDER BY ts_updated DESC) = 1
  )
  SELECT
    gs.id_session,
    MIN(gs.ts_started) AS ts_reception_started,
    (UNIX_TIMESTAMP(MIN(te.ts_created)) - UNIX_TIMESTAMP(MIN(gs.ts_started)))/60 AS total_minutes_reception_time
  FROM
    datalake_sauron_clean.session AS s
  INNER JOIN
    greenseer_sessions AS gs
      ON s.id = gs.id_session
      AND s.source_environment = "QuintoandarSupport"
  INNER JOIN
    datalake_quinto_messenger.chat AS c
      ON c.id_session = gs.id_session
  INNER JOIN
    datalake_quinto_messenger.task AS t
      ON t.id_chat = c.id_chat
  LEFT JOIN
    datalake_quinto_messenger.task_event AS te
      ON te.id_task = t.id_task
  GROUP BY 1
),
quinto_messenger_tasks AS (
  SELECT
    t.id_task,
    c.id_conversation,
    c.id_source AS id_session,
    t.id_agent,
    'whatsapp' AS origin,
    t.agent_email,
    t.seconds_to_first_response AS seconds_first_reply,
    t.seconds_to_first_response/60.0 AS task_minutes_wait_time,
    t.department,
    CASE
        WHEN t.department LIKE "%MX%" THEN "MX"
        ELSE "BR"
    END AS country_code,
    to.task_completion_reason AS completion_reason,
    t.transferred_from_dept,
    t.transferred_to_dept,
    t.transference_type,
    ttr.transference_reason,
    CAST(COALESCE(wm.number_of_departments,0) AS INT) AS number_of_departments,
    CAST(COALESCE(wm.number_of_tasks,0) AS INT) AS number_of_tasks,
    wm.number_of_tasks > 1 AS has_transfers,
    CASE
        WHEN t.seconds_to_first_response / 60 <= 15 THEN TRUE
        WHEN t.seconds_to_first_response / 60 > 15 THEN FALSE
        ELSE NULL
    END AS sla_achieved,
    t.customer_type_tag,
    t.contact_motivation_tag,
    t.contact_theme_tag,
    bot.total_minutes_reception_time,
    c.seconds_duration/60.0 AS minutes_full_resolution_time_calendar,
    ttm.total_talk_time AS seconds_total_talk_time,
    ttm.total_queue_time AS seconds_total_queue_time,
    ttm.total_wrap_up_time AS seconds_total_wrap_up_time,
    ttm.total_handling_time AS seconds_total_handling_time,
    bot.ts_reception_started,
    t.ts_created,
    t.ts_updated,
    t.ts_task_closed,
    t.ts_task_created,
    wm.ts_first_event,
    wm.ts_last_event
  FROM
    task AS t
  INNER JOIN
    datalake_quinto_messenger.channel AS c
      ON t.id_channel = c.id_channel
  LEFT JOIN
    chatbot_time_metrics_whatsapp AS bot
      ON c.id_source = bot.id_session
  LEFT JOIN
    whatsapp_metrics AS wm
      ON wm.id_conversation = c.id_source
  LEFT JOIN
    task_outcome AS to
      ON to.id_task = t.id_task
  LEFT JOIN
    task_transfer_reason AS ttr
      ON ttr.id_task = t.id_task
  LEFT JOIN
    twilio_time_metrics AS ttm
      ON ttm.id_channel = c.id_channel
  WHERE
    t.ts_created > '2020-08-20'
      AND c.channel_status <> 'missed'
  UNION ALL
  SELECT
    t.id_task,
    CAST(NULL AS STRING) AS id_conversation,
    c5a.id_session AS id_session,
    t.id_agent,
    'chat5a' AS origin,
    t.agent_email,
    t.seconds_to_first_response AS seconds_first_reply,
    t.seconds_to_first_response/60.0 AS task_minutes_wait_time,
    t.department,
    CASE
        WHEN t.department LIKE "%MX%" THEN "MX"
        ELSE "BR"
    END AS country_code,
    t.completion_reason,
    t.transferred_from_dept,
    t.transferred_to_dept,
    t.transference_type,
    ttr.transference_reason,
    CAST(COALESCE(cm.number_of_departments,0) AS INT) AS number_of_departments,
    CAST(COALESCE(cm.number_of_tasks,0) AS INT) AS number_of_tasks,
    cm.number_of_tasks > 1 AS has_transfers,
    CASE
        WHEN t.seconds_to_first_response / 60 <= 15 THEN TRUE
        WHEN t.seconds_to_first_response / 60 > 15 THEN FALSE
        ELSE NULL
    END AS sla_achieved,
    t.customer_type_tag,
    t.contact_motivation_tag,
    t.contact_theme_tag,
    bot.total_minutes_reception_time,
    (UNIX_TIMESTAMP(c5a.ts_updated) - UNIX_TIMESTAMP(c5a.ts_created))/60.0 AS minutes_full_resolution_time_calendar,
    ttm.total_talk_time AS seconds_total_talk_time,
    ttm.total_queue_time AS seconds_total_queue_time,
    ttm.total_wrap_up_time AS seconds_total_wrap_up_time,
    ttm.total_handling_time AS seconds_total_handling_time,
    bot.ts_reception_started,
    t.ts_created,
    t.ts_updated,
    t.ts_task_closed,
    t.ts_task_created,
    cm.ts_first_event,
    cm.ts_last_event
  FROM
    datalake_quinto_messenger.chat AS c5a
  INNER JOIN
    task AS t
      ON t.id_chat = c5a.id_chat
  LEFT JOIN
    chatbot_time_metrics_chat_inapp AS bot
      ON c5a.id_session = bot.id_session
  LEFT JOIN
    chat5a_metrics AS cm
      ON cm.id_session = c5a.id_session
  LEFT JOIN
    task_transfer_reason AS ttr
      ON ttr.id_task = t.id_task
  LEFT JOIN
    twilio_time_metrics AS ttm
      ON ttm.id_channel = c5a.id_channel
),
csat AS (
  SELECT
    c.id_ticket,
    sa.rating AS csat_score,
    c.group_name,
    sa.comment,
    CASE
        WHEN sa.is_solved = TRUE THEN TRUE
        WHEN sa.is_solved = FALSE THEN FALSE
        ELSE NULL
    END AS is_solved,
    sa.ts_created AS ts_csat_response,
    ROW_NUMBER() OVER (PARTITION BY c.id_ticket ORDER BY sa.ts_created) AS rw_number_asc,
    ROW_NUMBER() OVER (PARTITION BY c.id_ticket ORDER BY sa.ts_created DESC) AS rw_number_desc
  FROM
    datalake_chat_fup_clean.chats_chat AS c
  INNER JOIN
    datalake_chat_fup_clean.surveys_survey AS ss
      ON ss.id_chat = c.id
  LEFT JOIN
    datalake_chat_fup_clean.surveys_answer AS sa
      ON ss.id = sa.id_survey
  WHERE
    sa.id IS NOT NULL
    AND DATE(c.ts_attended) >= DATE('2018-01-01')
    AND sa.rating IS NOT NULL
),
chat_csat AS (
  SELECT
    ca.id_ticket,
    ca.csat_score AS last_csat_score,
    ca2.csat_score AS first_csat_score,
    ca.comment AS last_csat_comment,
    ca2.comment AS first_csat_comment,
    ca.ts_csat_response AS ts_last_response,
    ca2.ts_csat_response AS ts_first_response,
    ca.is_solved
  FROM
    csat AS ca
  INNER JOIN
    csat AS ca2
      ON ca2.id_ticket = ca.id_ticket
      AND ca2.rw_number_asc = 1
  WHERE
    ca.rw_number_desc = 1
),
zendesk_ticket_info AS (
  SELECT DISTINCT
    id_ticket,
    id_session,
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
tickets_with_task AS (
  SELECT DISTINCT
    zti.id_ticket,
    zti.status,
    COALESCE(
      NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(zti.custom_fields, '$.Ticket do contato'), '(WT[a-z0-9]{{20,40}})', 1), ''),
      REGEXP_EXTRACT(zti.description, '(WT[a-z0-9]{{20,40}})', 1)
    ) AS twilio_task_whatsapp,
    REGEXP_EXTRACT(GET_JSON_OBJECT(zti.custom_fields, '$.TaskSid Twilio'), '(WT[a-z0-9]{{20,40}})', 1) AS twilio_task_chat_inapp,
    zti.tags,
    zti.zendesk_ticket_department,
    zti.ts_created,
    zti.ts_solved
  FROM
    zendesk_ticket_info AS zti
),
total_tickets AS (
  SELECT
    qmt.id_session,
    t.id_ticket,
    t.status,
    t.twilio_task_whatsapp AS front_task,
    t.tags,
    t.zendesk_ticket_department,
    t.ts_created,
    t.ts_solved
  FROM
    tickets_with_task AS t
  INNER JOIN
    quinto_messenger_tasks AS qmt
      ON qmt.id_task = t.twilio_task_whatsapp
  UNION ALL
  SELECT
    qmt.id_session,
    t.id_ticket,
    t.status,
    t.twilio_task_chat_inapp AS front_task,
    t.tags,
    t.zendesk_ticket_department,
    t.ts_created,
    t.ts_solved
  FROM
    tickets_with_task AS t
  INNER JOIN
    quinto_messenger_tasks AS qmt
      ON qmt.id_task = t.twilio_task_chat_inapp
),
chat_back_tickets AS (
  SELECT
    tt.id_ticket AS back_ticket,
    tt.status AS back_ticket_status,
    zti.id_ticket AS front_ticket,
    tt.front_task,
    tt.ts_created,
    tt.ts_solved
  FROM
    total_tickets AS tt
  LEFT JOIN
    datalake_gsheets_clean.department_control AS dc
      ON dc.department = tt.zendesk_ticket_department
  INNER JOIN
    zendesk_ticket_info AS zti
      ON tt.id_session = zti.id_session
  WHERE
    (tt.tags LIKE '%tarefa_atendimento_escalado%' OR LOWER(dc.front_or_back) = 'back')
    AND (tt.tags NOT LIKE '%bot_end_conversation%' AND tt.tags NOT LIKE '%closed_by_merge%')
),
chat_back_tickets_metrics AS (
  WITH last_and_first_back_tickets_timestamps AS (
    SELECT
      front_ticket,
      CONCAT_WS(',' , COLLECT_SET(back_ticket)) AS back_ticket_list,
      SUM(CAST(back_ticket_status IN ('closed','deleted','solved') AS SMALLINT))/CAST(COUNT(DISTINCT back_ticket) AS FLOAT) != 1 AS is_open_back_ticket,
      MIN(ts_created) AS ts_first_created,
      MAX(ts_solved) AS ts_last_solved
    FROM
      chat_back_tickets
    GROUP BY 1
  )
  SELECT
    cbt.*,
    lt.is_open_back_ticket,
    lt.back_ticket_list,
    lt.ts_first_created,
    CAST((TO_UNIX_TIMESTAMP(lt.ts_last_solved) - TO_UNIX_TIMESTAMP(lt.ts_first_created))/60.0 AS DOUBLE) AS total_backoffice_minutes_time
  FROM
    chat_back_tickets AS cbt
  INNER JOIN
    last_and_first_back_tickets_timestamps AS lt
      ON lt.front_ticket = cbt.front_ticket
        AND lt.ts_last_solved = cbt.ts_solved
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY cbt.front_ticket ORDER BY lt.ts_first_created DESC) = 1
),
-- TODO: this CTE should be revisited, current rule is to keep the last ticket of a session.
zendesk_tickets_unique AS (
  WITH tickets_unique_whatsapp AS (
    SELECT
      tfm.id_session,
      MAX(tfm.id_ticket) AS id_ticket
    FROM
      datalake_zendesk_ticket_funnels.tickets_funnel_metrics AS tfm
    INNER JOIN
      datalake_quinto_messenger.channel AS c
        ON c.id_source = tfm.id_session
    GROUP BY 1
  ),
  tickets_unique_chat5a AS (
    SELECT
      tfm.id_session,
      MAX(tfm.id_ticket) AS id_ticket
    FROM
      datalake_zendesk_ticket_funnels.tickets_funnel_metrics AS tfm
    INNER JOIN
      datalake_quinto_messenger.chat AS c
        ON c.id_session = tfm.id_session
    GROUP BY 1
  )
  SELECT
    *
  FROM
    tickets_unique_whatsapp
  UNION ALL
  SELECT
    *
  FROM
    tickets_unique_chat5a
),
first_last_department AS (
  SELECT
    qmt.id_task,
    zti.id_ticket,
    qmt.id_session,
    FIRST(qmt.department) OVER (PARTITION BY zti.id_ticket ORDER BY qmt.ts_task_created ASC) AS first_department,
    FIRST(qmt.department) OVER (PARTITION BY zti.id_ticket ORDER BY qmt.ts_task_created DESC) AS last_department
  FROM
    quinto_messenger_tasks AS qmt
  INNER JOIN
    zendesk_ticket_info AS zti
      ON zti.id_session = qmt.id_session
)
SELECT DISTINCT
  qmt.id_task AS id_segment,
  zti.id_ticket,
  qmt.id_conversation,
  qmt.id_session,
  qmt.id_agent,
  zti.id_user,
  zti.id_contract,
  FIRST(qmt.agent_email) OVER (PARTITION BY zti.id_ticket ORDER BY qmt.ts_task_created) AS first_agent_email,
  FIRST(qmt.agent_email) OVER (PARTITION BY zti.id_ticket ORDER BY qmt.ts_task_created DESC) AS last_agent_email,
  qmt.origin AS ticket_origin,
  qmt.agent_email,
  qmt.department,
  qmt.country_code,
  zti.zendesk_ticket_department AS zendesk_department,
  ldep.first_department,
  ldep.last_department,
  qmt.completion_reason,
  qmt.transferred_from_dept,
  qmt.transferred_to_dept,
  qmt.transference_type,
  zti.request_type,
  zti.client_type,
  zti.step_tag,
  zti.customer_type_tag,
  zti.contact_motivation_tag,
  zti.contact_theme_tag,
  zti.contact_theme_detail_tag,
  zti.tags,
  zti.status,
  dc.journey_step,
  dc.team,
  dc.area,
  zti.custom_fields,
  CAST((TO_UNIX_TIMESTAMP(COALESCE(bt.ts_solved, qmt.ts_last_event)) - TO_UNIX_TIMESTAMP(qmt.ts_reception_started))/60.0 AS DOUBLE) AS frt,
  bt.back_ticket AS last_back_ticket,
  bt.back_ticket_list,
  bt.total_backoffice_minutes_time,
  CAST((TO_UNIX_TIMESTAMP(bt.ts_first_created) - TO_UNIX_TIMESTAMP(qmt.ts_last_event))/60.0 AS DOUBLE) AS total_minutes_front_to_open_back_ticket_time,
  qmt.seconds_first_reply,
  qmt.task_minutes_wait_time AS segment_minutes_wait_time,
  qmt.number_of_departments,
  qmt.number_of_tasks AS number_of_segments,
  qmt.sla_achieved,
  CAST(qmt.minutes_full_resolution_time_calendar AS DOUBLE) AS minutes_full_resolution_time_calendar,
  zti.minutes_first_resolution_time_calendar,
  zti.minutes_first_resolution_time_business,
  zti.replies,
  zti.reopens,
  qmt.total_minutes_reception_time,
  qmt.seconds_total_talk_time/60.0 AS total_minutes_talk_time,
  qmt.seconds_total_queue_time/60.0 AS total_minutes_queue_time,
  qmt.seconds_total_wrap_up_time/60.0 AS total_minutes_wrap_up_time,
  qmt.seconds_total_handling_time/60.0 AS total_minutes_handling_time,
  FIRST(qmt.id_task) OVER (PARTITION BY zti.id_ticket ORDER BY qmt.ts_task_created DESC) = qmt.id_task AS is_last_segment,
  FIRST(qmt.id_task) OVER (PARTITION BY zti.id_ticket ORDER BY qmt.ts_task_created ASC) = qmt.id_task AS is_first_segment,
  qmt.transference_reason,
  qmt.has_transfers,
  zti.tags LIKE '%bot_end_conversation%' AS is_bot,
  zti.tags LIKE '%closed_by_merge%' AS is_closed_by_merge,
  CASE
    WHEN tags LIKE "%chat_idled_finished%" THEN "IDLED"
    ELSE "COMPLETED"
  END AS service_status,
  CASE
    WHEN dc.front_or_back = 'Front' THEN 'front'
    WHEN dc.front_or_back = 'Back' OR zti.tags LIKE '%tarefa_atendimento_escalado%' THEN 'back'
    ELSE 'undefined'
  END AS front_or_back,
  bt.front_ticket IS NOT NULL AS has_back_ticket,
  bt.is_open_back_ticket,
  cc.id_ticket IS NOT NULL AS is_csat_answered,
  cc.is_solved,
  cc.first_csat_score,
  cc.last_csat_score,
  cc.last_csat_score AS csat_score,
  cc.last_csat_comment AS csat_comment,
  cc.last_csat_comment,
  cc.first_csat_comment,
  cc.ts_first_response AS ts_csat_first_response,
  cc.ts_last_response AS ts_csat_last_response,
  cc.ts_last_response AS ts_csat_response,
  qmt.ts_created,
  qmt.ts_updated,
  qmt.ts_first_event AS ts_ticket_started,
  qmt.ts_last_event AS ts_ticket_ended,
  qmt.ts_task_closed AS ts_segment_closed,
  qmt.ts_task_created AS ts_segment_created
FROM
  quinto_messenger_tasks AS qmt
INNER JOIN
  zendesk_ticket_info AS zti
    ON zti.id_session = qmt.id_session
INNER JOIN
  first_last_department AS ldep
    ON ldep.id_session = qmt.id_session
INNER JOIN
  zendesk_tickets_unique AS ztu
    ON ztu.id_ticket = zti.id_ticket
LEFT JOIN
  datalake_gsheets_clean.department_control AS dc
    ON dc.department = ldep.last_department
LEFT JOIN
  chat_csat AS cc
    ON cc.id_ticket = zti.id_ticket
LEFT JOIN
  chat_back_tickets_metrics AS bt
    ON bt.front_ticket = zti.id_ticket
