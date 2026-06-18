WITH task_queues_ranked AS (
  SELECT
    id_task,
    id_queue,
    queue_name,
    ROW_NUMBER() OVER(PARTITION BY id_task ORDER BY ts_updated DESC) AS rn
  FROM
    datalake_quinto_messenger_clean.task_event
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE("{load_start_date}") - INTERVAL 60 DAY AND DATE("{load_end_date}")
),
task_queues AS (
  SELECT
    id_task,
    id_queue,
    queue_name
  FROM
    task_queues_ranked
  WHERE
    rn = 1
),
sauron_session_data AS (
  SELECT
    id AS id_session,
    public_id AS id_sss_session,
    get_json_object(user_data, '$.user_id') AS id_user,
    get_json_object(user_data, '$.user_phone') AS user_phone,
    get_json_object(user_data, '$.user_email') AS user_email,
    created_by,
    source,
    source_environment
  FROM
    datalake_sauron_clean.session
  WHERE
    year >= YEAR(DATE("{load_start_date}") - INTERVAL 3 MONTH) -- we need to check all sessions as they do not have a fixed lifetime
),
sss_session_data AS (
  SELECT
    NULL AS id_session,
    public_id AS id_sss_session,
    get_json_object(user_data, '$.user_id') AS id_user,
    get_json_object(user_data, '$.user_phone') AS user_phone,
    get_json_object(user_data, '$.user_email') AS user_email,
    created_by,
    source,
    source_env AS source_environment
  FROM
    datalake_support_session_service_clean.support_session
  WHERE
    DATE(ts_updated) BETWEEN DATE("{load_start_date}") - INTERVAL 7 DAY AND DATE("{load_end_date}")
),
-- mas tem whastapp aqui dentro também
inapp_sessions AS (
  SELECT DISTINCT
    c.id_chat,
    c.id_session, -- sessões do sauron OU sessões do SSS
    COALESCE(s.id_session, ss.id_session, s_hash.id_session) AS id_sauron_session,
    COALESCE(ss.id_sss_session, s.id_sss_session, s_hash.id_sss_session) AS id_sss_session,
    get_json_object(c.attributes, '$.channel_type') AS channel_type,
    COALESCE(ss.id_user, s.id_user, s_hash.id_user) AS id_user,
    COALESCE(ss.user_phone, s.user_phone, s_hash.user_phone) AS user_phone,
    COALESCE(ss.user_email, s.user_email, s_hash.user_email) AS user_email,
    COALESCE(ss.created_by, s.created_by) AS created_by,
    COALESCE(ss.source, s.source, s_hash.source) AS source,
    COALESCE(ss.source_environment, s.source_environment, s_hash.source_environment) AS source_environment
  FROM
    datalake_quinto_messenger_clean.chat AS c
  LEFT JOIN
    sss_session_data AS ss
      ON ss.id_sss_session = c.id_session
      AND c.source = 'support_session'
  LEFT JOIN
    sauron_session_data AS s
      ON s.id_session = TRY_CAST(c.id_session AS BIGINT)
      AND c.source = 'sauron'
  LEFT JOIN 
    sauron_session_data AS s_hash
    ON s_hash.id_sss_session = c.id_session
    AND c.source = 'sauron'
  WHERE
    MAKE_DATE(c.year, c.month, c.day) BETWEEN DATE("{load_start_date}") - INTERVAL 7 DAY AND DATE("{load_end_date}")
),
-- em breve essa cte poderá ser removida, ja que whatsapp vai migrar pra chat
whatsapp_sessions AS (
  SELECT DISTINCT
    c.id_channel,
    CAST(c.id_session AS INTEGER) AS id_session,
    s.id_session AS id_sauron_session,
    s.id_user,
    s.user_phone,
    s.user_email,
    s.created_by,
    s.source,
    s.source_environment
  FROM
    datalake_quinto_messenger_clean.channel AS c
  LEFT JOIN
    sauron_session_data AS s
      ON s.id_session = c.id_session
  WHERE
    MAKE_DATE(c.year, c.month, c.day) BETWEEN DATE("{load_start_date}") - INTERVAL 7 DAY AND DATE("{load_end_date}")
),
tasks_ranked AS (
  SELECT
    id_channel,
    id_chat,
    id_task,
    id_worker,
    worker_email,
    CASE
      WHEN channel_type = 'whatsapp' THEN
        COALESCE(customer_phone_number, REPLACE(customer_contact_info, "whatsapp:+", ""))
      ELSE NULL
    END AS from_phone_number,
    REPLACE(twilio_phone_number, "whatsapp:+", "") AS twilio_phone_number,
    customer_email,
    channel_type,
    task_status,
    task_outcome,
    completion_reason AS task_completion_reason,
    channel_status,
    bpo_name,
    bpo_selection_reason,
    assigned_to,
    seconds_to_first_response,
    is_forwarded,
    is_per_team_task,
    is_spoc_task,
    ts_created,
    ts_updated,
    task_attributes,
    id_source_ctwa,
    url_source_ctwa,
    type_source_ctwa,
    total_inactivity_time,
    last_inactivity_time,
    ROW_NUMBER() OVER(PARTITION BY id_task ORDER BY ts_updated DESC) AS rn
  FROM
    datalake_quinto_messenger_clean.task
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE("{load_start_date}") - INTERVAL 7 DAY AND DATE("{load_end_date}")
),
tasks AS (
  SELECT
    id_channel,
    id_chat,
    id_task,
    id_worker,
    worker_email,
    from_phone_number,
    twilio_phone_number,
    customer_email,
    channel_type,
    task_status,
    task_outcome,
    task_completion_reason,
    channel_status,
    bpo_name,
    bpo_selection_reason,
    assigned_to,
    seconds_to_first_response,
    is_forwarded,
    is_per_team_task,
    is_spoc_task,
    ts_created,
    ts_updated,
    task_attributes,
    id_source_ctwa,
    url_source_ctwa,
    type_source_ctwa,
    total_inactivity_time,
    last_inactivity_time
  FROM
    tasks_ranked
  WHERE
    rn = 1
)
SELECT
  t.id_channel,
  t.id_task,
  CAST(COALESCE(ias.id_sauron_session, ws.id_session) AS STRING) AS id_session,
  ias.id_sss_session AS id_sss_session,
  COALESCE(ias.id_user, ws.id_user) AS id_user,
  t.id_worker,
  tq.id_queue,
  t.id_source_ctwa,
  tq.queue_name,
  COALESCE(ias.user_email, ws.user_email, t.customer_email) AS customer_email,
  COALESCE(ias.user_phone, ws.user_phone, t.from_phone_number) AS customer_phone_number,
  t.twilio_phone_number,
  CASE WHEN
    COALESCE(ias.source, ws.source) = 'internal_chat' THEN 'in app'
    ELSE COALESCE(ias.source, ws.source)
    END AS origin,
  CASE
    WHEN COALESCE(ias.created_by, ws.created_by) = 'hsm_sent' THEN 'outbound'
    WHEN t.is_spoc_task IS TRUE AND COALESCE(ias.created_by, ws.created_by) = 'human_support' THEN 'inbound'
    WHEN t.is_spoc_task IS TRUE AND COALESCE(ias.created_by, ws.created_by) = 'user' THEN 'outbound'
    ELSE 'inbound'
  END AS direction,
  t.worker_email,
  t.channel_type,
  t.task_status,
  t.task_outcome,
  t.task_completion_reason,
  t.bpo_name,
  t.bpo_selection_reason,
  t.seconds_to_first_response,
  t.is_forwarded,
  t.is_per_team_task,
  t.is_spoc_task,
  CASE 
    WHEN COALESCE(ias.source_environment, ws.source_environment) IN ('isaias_inbound', 'isaias_inbound_main') THEN TRUE
    ELSE FALSE
  END AS is_isaias_session,
  t.url_source_ctwa,
  t.type_source_ctwa,
  t.total_inactivity_time, 
  t.last_inactivity_time,
  t.ts_created,
  t.ts_updated AS ts_ended,
  t.task_attributes,
  YEAR(t.ts_created) AS year,
  MONTH(t.ts_created) AS month,
  DAY(t.ts_created) AS day
FROM
  tasks AS t
LEFT JOIN
  inapp_sessions AS ias
    ON ias.id_chat = t.id_chat
LEFT JOIN
  whatsapp_sessions AS ws
    ON ws.id_channel = t.id_channel
LEFT JOIN
  task_queues AS tq
    ON tq.id_task = t.id_task
WHERE
  COALESCE(ias.id_session, ws.id_session) IS NOT NULL
