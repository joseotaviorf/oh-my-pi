WITH inbound_leads AS (
  SELECT
    hl.id_lead_ebdb,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.taskId') AS STRING) AS id_task,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.aiCoreSessionId') AS STRING) AS id_ai_core_session,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.origin') AS STRING) AS origin,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.ctwaClid') AS STRING) AS ctwa_clid,
    REGEXP_EXTRACT(p.phone_number, '[0-9]+', 0) AS phone_number,
    amd.ts_created
  FROM datalake_rene_descartes_clean.house_lead AS hl
  INNER JOIN datalake_rene_descartes_clean.acquisition_misc_data AS amd
    ON hl.id_acquisition = amd.id
  LEFT JOIN datalake_rene_descartes_clean.phone AS p
    ON p.id_owner = hl.id_house_owner
  WHERE
    1 = 1
    AND CAST(amd.ts_created AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
    AND CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.origin') AS STRING) IN ('Inbound', 'OwnerConversionPWA', 'Isaias')
), support_sessions AS (
  SELECT
    s.id AS id_session,
    s.source_environment,
    s.department,
    REGEXP_EXTRACT(COALESCE(s.user_phone, GET_JSON_OBJECT(s.user_data, '$.user_phone')), '[0-9]+', 0) AS phone_number,
    GET_JSON_OBJECT(s.metadata, '$.extra_params.ctwa_clid') AS ctwa_clid,
    GET_JSON_OBJECT(s.metadata, '$.extra_params.referral_source_id') AS id_source_ctwa,
    GET_JSON_OBJECT(s.metadata, '$.extra_params.referral_source_url') AS url_source_ctwa,
    GET_JSON_OBJECT(s.metadata, '$.extra_params.referral_source_type') AS type_source_ctwa,
    s.ts_created,
    s.ts_updated
  FROM datalake_sauron_clean.session AS s
  WHERE
    1 = 1
    AND (
      (
        s.ts_created < CAST('2025-10-11' AS DATE) AND s.source IN ('call_in_app', 'call')
      )
      OR NOT s.source IN ('call_in_app', 'call')
    ) /* hardcoded fix regarding support session migration */
    AND s.ts_created >= CAST('{load_start_date}' AS DATE) - INTERVAL '365' DAYS
    AND NOT COALESCE(s.user_phone, GET_JSON_OBJECT(s.user_data, '$.user_phone')) IS NULL
  UNION ALL
  SELECT
    s.id AS id_session,
    s.source_env AS source_environment,
    s.department,
    REGEXP_EXTRACT(COALESCE(s.user_phone, GET_JSON_OBJECT(s.user_data, '$.user_phone')), '[0-9]+', 0) AS phone_number,
    GET_JSON_OBJECT(s.metadata, '$.extra_params.ctwa_clid') AS ctwa_clid,
    GET_JSON_OBJECT(s.metadata, '$.extra_params.referral_source_id') AS id_source_ctwa,
    GET_JSON_OBJECT(s.metadata, '$.extra_params.referral_source_url') AS url_source_ctwa,
    GET_JSON_OBJECT(s.metadata, '$.extra_params.referral_source_type') AS type_source_ctwa,
    s.ts_created,
    s.ts_updated
  FROM datalake_support_session_service_clean.support_session AS s
  LEFT ANTI JOIN datalake_sauron_clean.session AS sauron
    ON s.id = sauron.id
    AND s.source = 'internal_chat'
    AND sauron.ts_created >= CAST('{load_start_date}' AS DATE) - INTERVAL '365' DAYS
  WHERE
    1 = 1
    AND s.ts_created >= CAST('2025-10-11' AS DATE) /* hardcoded fix regarding support session migration */
    AND s.source IN ('call_in_app', 'call', 'internal_chat')
    AND s.ts_created >= CAST('{load_start_date}' AS DATE) - INTERVAL '365' DAYS
    AND NOT COALESCE(s.user_phone, GET_JSON_OBJECT(s.user_data, '$.user_phone')) IS NULL
), support_tasks AS (
  SELECT
    ch.id_task,
    ch.id_session,
    1 AS task_priority,
    ch.queue_name AS department,
    REGEXP_EXTRACT(ch.twilio_phone_number, '[0-9]+', 0) AS quinto_andar_phone_number,
    ch.ts_created AS ts_task_created
  FROM datalake_customer_support.chats AS ch
  UNION
  SELECT
    ca.id_task,
    ca.id_session,
    CASE WHEN ca.direction = 'inbound' THEN 2 WHEN ca.direction = 'outbound' THEN 3 END AS task_priority,
    ca.queue_name AS department,
    CASE
      WHEN ca.direction = 'inbound'
      THEN REGEXP_EXTRACT(ca.to_phone_number, '[0-9]+', 0)
      WHEN ca.direction = 'outbound'
      THEN REGEXP_EXTRACT(ca.from_phone_number, '[0-9]+', 0)
    END AS quinto_andar_phone_number,
    ca.ts_reservation_created AS ts_task_created
  FROM datalake_customer_support.calls AS ca
), attribution AS (
  /* best-case scenario where the task id comes from the source system */
  SELECT
    id_lead_ebdb,
    id_session,
    id_task,
    source_environment,
    department,
    phone_number,
    quinto_andar_phone_number,
    ctwa_clid,
    id_source_ctwa,
    url_source_ctwa,
    type_source_ctwa,
    ts_created
  FROM (
    /* best-case scenario where the task id comes from the source system */
    SELECT
      inbound_leads.id_lead_ebdb,
      support_sessions.id_session,
      inbound_leads.id_task,
      support_sessions.source_environment,
      support_tasks.department,
      COALESCE(inbound_leads.phone_number, support_sessions.phone_number) AS phone_number,
      support_tasks.quinto_andar_phone_number,
      COALESCE(inbound_leads.ctwa_clid, support_sessions.ctwa_clid) AS ctwa_clid,
      support_sessions.id_source_ctwa,
      support_sessions.url_source_ctwa,
      support_sessions.type_source_ctwa,
      support_sessions.ts_created,
      ROW_NUMBER() OVER (PARTITION BY inbound_leads.id_lead_ebdb ORDER BY support_tasks.ts_task_created DESC) AS _w,
      support_tasks.ts_task_created
    FROM inbound_leads
    INNER JOIN support_tasks
      ON support_tasks.id_task = inbound_leads.id_task
    INNER JOIN support_sessions
      ON support_tasks.id_session = support_sessions.id_session
  ) AS _t
  WHERE
    _w = 1
  UNION
  /* best-case scenario where the session id comes from the source system */
  SELECT
    id_lead_ebdb,
    id_session,
    id_task,
    source_environment,
    department,
    phone_number,
    quinto_andar_phone_number,
    ctwa_clid,
    id_source_ctwa,
    url_source_ctwa,
    type_source_ctwa,
    ts_created
  FROM (
    /* best-case scenario where the session id comes from the source system */
    SELECT
      il.id_lead_ebdb,
      cs.id_sauron_session AS id_session,
      '-1' AS id_task,
      support_sessions.source_environment,
      support_sessions.department,
      COALESCE(il.phone_number, support_sessions.phone_number) AS phone_number,
      REGEXP_EXTRACT(wpp_channel.twilio_phone_number, '[0-9]+', 0) AS quinto_andar_phone_number,
      COALESCE(il.ctwa_clid, support_sessions.ctwa_clid) AS ctwa_clid,
      support_sessions.id_source_ctwa,
      support_sessions.url_source_ctwa,
      support_sessions.type_source_ctwa,
      support_sessions.ts_created,
      ROW_NUMBER() OVER (PARTITION BY il.id_lead_ebdb ORDER BY wpp_channel.ts_created DESC) AS _w
    FROM inbound_leads AS il
    INNER JOIN datalake_copilot_service_clean.session AS cs
      ON il.id_ai_core_session = cs.id_external
      AND cs.ts_created >= CAST('{load_start_date}' AS DATE) - INTERVAL '7' DAYS
    INNER JOIN support_sessions
      ON cs.id_sauron_session = support_sessions.id_session
    LEFT JOIN datalake_quinto_messenger_clean.channel AS wpp_channel
      ON wpp_channel.id_session = cs.id_sauron_session
      AND wpp_channel.ts_created >= CAST('{load_start_date}' AS DATE) - INTERVAL '7' DAYS
  ) AS _t
  WHERE
    _w = 1
), indirect_attribution AS (
  SELECT
    id_lead_ebdb,
    id_session,
    id_task,
    source_environment,
    department,
    phone_number,
    quinto_andar_phone_number,
    ctwa_clid,
    id_source_ctwa,
    url_source_ctwa,
    type_source_ctwa,
    ts_created
  FROM (
    SELECT
      il.id_lead_ebdb,
      ss.id_session,
      st.id_task,
      ss.source_environment,
      st.department,
      il.phone_number,
      st.quinto_andar_phone_number,
      ss.ctwa_clid,
      ss.id_source_ctwa,
      ss.url_source_ctwa,
      ss.type_source_ctwa,
      ss.ts_created,
      ROW_NUMBER() OVER (PARTITION BY il.id_lead_ebdb ORDER BY st.task_priority ASC, st.ts_task_created DESC) AS _w,
      st.task_priority,
      st.ts_task_created
    FROM inbound_leads AS il
    INNER JOIN support_sessions AS ss
      ON il.phone_number = ss.phone_number
      AND il.ts_created >= ss.ts_created - INTERVAL '30' MINUTES
      AND il.ts_created <= ss.ts_updated + INTERVAL '30' MINUTES
    INNER JOIN support_tasks AS st
      ON st.id_session = ss.id_session
      AND il.ts_created > st.ts_task_created
      AND il.ts_created <= st.ts_task_created + INTERVAL '150' MINUTES
    LEFT JOIN support_tasks AS ops_deviation_fix
      ON ops_deviation_fix.id_task = il.id_task
    WHERE
      il.origin = 'OwnerConversionPWA'
      AND COALESCE(ops_deviation_fix.task_priority, 0) <> 1 /* ignores chat tasks and fix possible calls tasks input deviations or the absence of an input */
  ) AS _t
  WHERE
    _w = 1
), final_attribution AS (
  SELECT
    id_lead_ebdb,
    id_session,
    id_task,
    source_environment,
    department,
    phone_number,
    quinto_andar_phone_number,
    ctwa_clid,
    id_source_ctwa,
    url_source_ctwa,
    type_source_ctwa,
    ts_created
  FROM indirect_attribution
  UNION
  SELECT
    att.id_lead_ebdb,
    att.id_session,
    att.id_task,
    att.source_environment,
    att.department,
    att.phone_number,
    att.quinto_andar_phone_number,
    att.ctwa_clid,
    att.id_source_ctwa,
    att.url_source_ctwa,
    att.type_source_ctwa,
    att.ts_created
  FROM attribution AS att
  LEFT JOIN indirect_attribution
    ON indirect_attribution.id_lead_ebdb = att.id_lead_ebdb
  WHERE
    indirect_attribution.id_lead_ebdb IS NULL
)
SELECT
  id_lead_ebdb,
  id_session,
  id_task,
  id_source_ctwa,
  source_environment,
  department,
  phone_number,
  quinto_andar_phone_number,
  ctwa_clid,
  url_source_ctwa,
  type_source_ctwa,
  ts_created
FROM (
  SELECT
    final_attribution.id_lead_ebdb,
    final_attribution.id_session,
    final_attribution.id_task,
    COALESCE(final_attribution.id_source_ctwa, support_sessions.id_source_ctwa) AS id_source_ctwa,
    final_attribution.source_environment,
    final_attribution.department,
    final_attribution.phone_number,
    final_attribution.quinto_andar_phone_number,
    COALESCE(final_attribution.ctwa_clid, support_sessions.ctwa_clid) AS ctwa_clid,
    COALESCE(final_attribution.url_source_ctwa, support_sessions.url_source_ctwa) AS url_source_ctwa,
    COALESCE(final_attribution.type_source_ctwa, support_sessions.type_source_ctwa) AS type_source_ctwa,
    final_attribution.ts_created,
    ROW_NUMBER() OVER (PARTITION BY final_attribution.id_lead_ebdb ORDER BY support_sessions.ts_created DESC) AS _w
  FROM final_attribution
  LEFT JOIN support_sessions
    ON support_sessions.phone_number = final_attribution.phone_number
    AND support_sessions.ts_created <= final_attribution.ts_created
    AND NOT support_sessions.ctwa_clid IS NULL
) AS _t
WHERE
  _w = 1