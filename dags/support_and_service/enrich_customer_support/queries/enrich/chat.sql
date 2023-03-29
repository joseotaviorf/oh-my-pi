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
chat_metrics AS (
  SELECT
    id_conversation,
    COUNT(DISTINCT t.id_task) AS number_of_tasks,
    COUNT(DISTINCT task_queue_name) AS number_of_departments,
    MAX(te.ts_created_local) AS ts_last_event,
    MIN(te.ts_created_local) AS ts_first_event
  FROM
    datalake_quinto_messenger.task AS t
  INNER JOIN
    datalake_quinto_messenger.task_event AS te
      ON t.id_task = te.id_task
  GROUP BY 1
),
task AS (
  SELECT
    t.id_task,
    t.id_channel,
    t.id_agent,
    t.id_chat,
    t.agent_email,
    tt.department,
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
  SELECT
    ctm.id_conversation,
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
    datalake_twilio_flex_insights_clean.conversation_time_metrics AS ctm
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
      RANK() OVER (PARTITION BY id_session ORDER BY ts_updated DESC) = 1
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
    ac.manager AS agent_manager,
    ac.agent_name,
    ac.agent_company,
    ac.dt_start,
    t.seconds_to_first_response AS seconds_first_reply,
    t.seconds_to_first_response/60.0 AS task_minutes_wait_time,
    t.department,
    to.task_completion_reason AS completion_reason,
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
    c.seconds_duration/60.0 AS minutes_full_resolution_time_calendar,
    ctm.total_talk_time AS seconds_total_talk_time,
    ctm.total_queue_time AS seconds_total_queue_time,
    ctm.total_wrap_up_time AS seconds_total_wrap_up_time,
    ctm.total_handling_time AS seconds_total_handling_time,
    bot.ts_reception_started,
    t.ts_created,
    t.ts_updated,
    t.ts_task_closed,
    t.ts_task_created,
    cm.ts_first_event,
    cm.ts_last_event
  FROM
    datalake_quinto_messenger.channel AS c
  INNER JOIN
    task AS t
      ON t.id_channel = c.id_channel
  LEFT JOIN
    chatbot_time_metrics_whatsapp AS bot
      ON c.id_source = bot.id_session
  LEFT JOIN
    chat_metrics AS cm
      ON cm.id_conversation = c.id_source
  LEFT JOIN
    task_outcome AS to
      ON to.id_task = t.id_task
  LEFT JOIN
    task_transfer_reason AS ttr
      ON ttr.id_task = t.id_task
  LEFT JOIN
    datalake_gsheets_clean.agents_control AS ac
      ON t.agent_email = ac.email
  LEFT JOIN
    twilio_time_metrics AS ctm
      ON c.id_conversation = ctm.id_conversation
  WHERE
    c.ts_created > '2020-08-20'
      AND c.channel_status <> 'missed'
  UNION ALL
  SELECT
    t.id_task,
    CAST(NULL AS STRING) AS id_conversation,
    c5a.id_session AS id_session,
    t.id_agent,
    'chat5a' AS origin,
    t.agent_email,
    ac.manager AS agent_manager,
    ac.agent_name,
    ac.agent_company,
    ac.dt_start,
    t.seconds_to_first_response AS seconds_first_reply,
    t.seconds_to_first_response/60.0 AS task_minutes_wait_time,
    t.department,
    to.task_completion_reason AS completion_reason,
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
    ctm.total_talk_time AS seconds_total_talk_time,
    ctm.total_queue_time AS seconds_total_queue_time,
    ctm.total_wrap_up_time AS seconds_total_wrap_up_time,
    ctm.total_handling_time AS seconds_total_handling_time,
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
    chat_metrics AS cm
      ON cm.id_conversation = c5a.id_session
  LEFT JOIN
    task_outcome AS to
      ON to.id_task = t.id_task
  LEFT JOIN
    task_transfer_reason AS ttr
      ON ttr.id_task = t.id_task
  LEFT JOIN
    datalake_gsheets_clean.agents_control AS ac
      ON t.agent_email = ac.email
  LEFT JOIN
    datalake_twilio_flex_insights_clean.conversation_time_metrics AS ctm
      ON t.id_task = ctm.id_segment
  WHERE
    c5a.ts_created > '2020-08-20'
),
chat_csat AS(
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
    ss.ts_created AS ts_survey,
    sa.ts_created AS ts_csat_response
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
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY c.id_ticket ORDER BY sa.ts_created DESC) = 1
),
zendesk_ticket_info AS (
  SELECT DISTINCT
    tf.id_ticket,
    ftm.id_session,
    ftm.id_user,
    ftm.id_contract,
    tf.tags,
    tf.description,
    tf.status,
    tf.custom_fields,
    tf.group_name AS zendesk_ticket_department,
    ftm.minutes_first_resolution_calendar AS minutes_first_resolution_time_calendar,
    ftm.minutes_first_resolution_business AS minutes_first_resolution_time_business,
    ftm.reopens,
    ftm.replies,
    tf.request_type,
    tf.client_type,
    tf.step_tag,
    tf.customer_type_tag,
    tf.contact_motivation_tag,
    tf.contact_theme_tag,
    tf.contact_theme_detail_tag,
    ftm.ts_created_local AS ts_created,
    ftm.ts_solved_local AS ts_solved
  FROM
    datalake_zendesk_ticket_funnels.ticket_funnel AS tf
  INNER JOIN
    datalake_zendesk_ticket_funnels.tickets_funnel_metrics AS ftm
      ON tf.id_ticket = ftm.id_ticket
),
tickets_with_task AS (
  SELECT
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
  FIRST(qmt.id_agent) OVER (PARTITION BY zti.id_ticket ORDER BY qmt.ts_task_created ASC) AS id_first_agent,
  FIRST(qmt.id_agent) OVER (PARTITION BY zti.id_ticket ORDER BY qmt.ts_task_created DESC) AS id_last_agent,
  zti.id_user,
  zti.id_contract,
  qmt.origin AS ticket_origin,
  qmt.agent_email,
  qmt.agent_manager,
  qmt.agent_name,
  qmt.agent_company,
  cc.comment AS csat_comment,
  qmt.department,
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
    WHEN dc.front_or_back = 'Front' THEN 'front'
    WHEN dc.front_or_back = 'Back' OR zti.tags LIKE '%tarefa_atendimento_escalado%' THEN 'back'
    ELSE 'undefined'
  END AS front_or_back,
  bt.front_ticket IS NOT NULL AS has_back_ticket,
  bt.is_open_back_ticket,
  cc.id_ticket IS NOT NULL AS is_csat_answered,
  cc.is_solved,
  cc.csat_score,
  cc.group_name,
  cc.ts_survey,
  cc.ts_csat_response,
  qmt.dt_start AS dt_agent_start,
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
