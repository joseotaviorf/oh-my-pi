WITH inbound_leads AS ( -- all leads that could bring task ids or sessions ids
  SELECT
    hl.id_lead_ebdb,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.taskId') AS STRING) AS id_task,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.aiCoreSessionId') AS STRING) AS id_ai_core_session,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.origin') AS STRING) AS origin,
    CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.ctwaClid') AS STRING) AS ctwa_clid,
    REGEXP_EXTRACT(p.phone_number, '[0-9]+', 0) AS phone_number,
    amd.ts_created
  FROM
    datalake_rene_descartes_clean.house_lead AS hl
  INNER JOIN
    datalake_rene_descartes_clean.acquisition_misc_data AS amd
      ON hl.id_acquisition = amd.id
  LEFT JOIN
    datalake_rene_descartes_clean.phone AS p
      ON p.id_owner = hl.id_house_owner
  WHERE 1=1
    AND DATE(amd.ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND CAST(GET_JSON_OBJECT(amd.acquisition_campaign, '$.origin') AS STRING) IN ('Inbound', 'OwnerConversionPWA', 'Isaias')
),
support_sessions AS (
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
  FROM
    datalake_sauron_clean.session AS s
  WHERE 1=1
    AND ( -- hardcoded fix regarding support session migration
          (s.ts_created < DATE('2025-10-11') AND s.source IN ('call_in_app', 'call'))
          OR s.source NOT IN ('call_in_app', 'call')
    )
    AND s.ts_created >= DATE("{load_start_date}") - INTERVAL 365 DAYS
    AND COALESCE(s.user_phone, GET_JSON_OBJECT(s.user_data, '$.user_phone')) IS NOT NULL

  UNION ALL

  SELECT
    s.public_id AS id_session,
    s.source_env AS source_environment,
    s.department,
    REGEXP_EXTRACT(COALESCE(s.user_phone, GET_JSON_OBJECT(s.user_data, '$.user_phone')), '[0-9]+', 0) AS phone_number,
    GET_JSON_OBJECT(s.metadata, '$.extra_params.ctwa_clid') AS ctwa_clid,
    GET_JSON_OBJECT(s.metadata, '$.extra_params.referral_source_id') AS id_source_ctwa,
    GET_JSON_OBJECT(s.metadata, '$.extra_params.referral_source_url') AS url_source_ctwa,
    GET_JSON_OBJECT(s.metadata, '$.extra_params.referral_source_type') AS type_source_ctwa,
    s.ts_created,
    s.ts_updated
  FROM
    datalake_support_session_service_clean.support_session AS s
  LEFT ANTI JOIN datalake_sauron_clean.session AS sauron
    ON s.id = sauron.id
    AND s.source = 'internal_chat'
    AND sauron.ts_created >= DATE("{load_start_date}") - INTERVAL 365 DAYS
  WHERE 1=1
    AND s.ts_created >= DATE('2025-10-11') -- hardcoded fix regarding support session migration
    AND s.source IN ('call_in_app', 'call', 'internal_chat')
    AND s.ts_created >= DATE("{load_start_date}") - INTERVAL 365 DAYS
    AND COALESCE(s.user_phone, GET_JSON_OBJECT(s.user_data, '$.user_phone')) IS NOT NULL
),
support_tasks AS (
  SELECT
    ch.id_task,
    ch.id_session,
    ch.id_sss_session,
    1 AS task_priority,
    ch.queue_name AS department,
    REGEXP_EXTRACT(ch.twilio_phone_number, '[0-9]+', 0) AS quinto_andar_phone_number,
    ch.ts_created AS ts_task_created
  FROM
    datalake_customer_support.chats AS ch
  UNION
  SELECT
    ca.id_task,
    ca.id_session,
    ca.id_sss_session,
    CASE
      WHEN ca.direction = 'inbound' THEN 2
      WHEN ca.direction = 'outbound' THEN 3
    END task_priority,
    ca.queue_name AS department,
    CASE
      WHEN ca.direction = 'inbound' THEN REGEXP_EXTRACT(ca.to_phone_number, '[0-9]+', 0)
      WHEN ca.direction = 'outbound' THEN REGEXP_EXTRACT(ca.from_phone_number, '[0-9]+', 0)
    END AS quinto_andar_phone_number,
    ca.ts_reservation_created AS ts_task_created
  FROM
    datalake_customer_support.calls AS ca
),
support_task_session_links AS (
  SELECT
    st.id_task,
    ss.id_session
  FROM
    support_tasks AS st
  INNER JOIN
    support_sessions AS ss
      ON st.id_session = ss.id_session

  UNION

  SELECT
    st.id_task,
    ss.id_session
  FROM
    support_tasks AS st
  INNER JOIN
    support_sessions AS ss
      ON st.id_sss_session = ss.id_session
),
attribution_by_task AS (
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
      ROW_NUMBER() OVER (
        PARTITION BY inbound_leads.id_lead_ebdb
        ORDER BY support_tasks.ts_task_created DESC
      ) AS rn
    FROM
      inbound_leads
    INNER JOIN
      support_tasks
        ON support_tasks.id_task = inbound_leads.id_task
    INNER JOIN
      support_task_session_links
        ON support_task_session_links.id_task = support_tasks.id_task
    INNER JOIN
      support_sessions
        ON support_sessions.id_session = support_task_session_links.id_session
  )
  WHERE
    rn = 1
),
attribution_by_session AS (
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
      ROW_NUMBER() OVER (
        PARTITION BY il.id_lead_ebdb
        ORDER BY wpp_channel.ts_created DESC
      ) AS rn
    FROM
      inbound_leads AS il
    INNER JOIN
      datalake_copilot_service_clean.session AS cs
        ON il.id_ai_core_session = cs.id_external
          AND cs.ts_created >= DATE("{load_start_date}") - INTERVAL 7 DAYS
    INNER JOIN
      support_sessions
        ON cs.id_sauron_session = support_sessions.id_session
    LEFT JOIN
      datalake_quinto_messenger_clean.channel AS wpp_channel
        ON wpp_channel.id_session = cs.id_sauron_session
          AND wpp_channel.ts_created >= DATE("{load_start_date}") - INTERVAL 7 DAYS
  )
  WHERE
    rn = 1
),
attribution AS (
  SELECT * FROM attribution_by_task
  UNION
  SELECT * FROM attribution_by_session
),
indirect_attribution AS ( -- when we don't have the identifier coming from source system or we want to fix it
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
      ROW_NUMBER() OVER (
        PARTITION BY il.id_lead_ebdb
        ORDER BY st.task_priority ASC, st.ts_task_created DESC
      ) AS rn
    FROM
      inbound_leads AS il
    INNER JOIN
      support_sessions AS ss
        ON il.phone_number = ss.phone_number
          AND il.ts_created >= ss.ts_created - INTERVAL '30' MINUTES
          AND il.ts_created <= ss.ts_updated + INTERVAL '30' MINUTES
    INNER JOIN
      support_task_session_links AS tsl
        ON tsl.id_session = ss.id_session
    INNER JOIN
      support_tasks AS st
        ON st.id_task = tsl.id_task
          AND il.ts_created > st.ts_task_created
          AND il.ts_created <= st.ts_task_created + INTERVAL '150' MINUTES
    LEFT JOIN
      support_tasks AS ops_deviation_fix
        ON ops_deviation_fix.id_task = il.id_task
    WHERE
      il.origin = 'OwnerConversionPWA'
      AND COALESCE(ops_deviation_fix.task_priority, 0) <> 1 -- ignores chat tasks and fix possible calls tasks input deviations or the absence of an input
  )
  WHERE
    rn = 1
),
final_attribution AS (
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
  FROM
    indirect_attribution

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
  FROM
    attribution AS att
  LEFT JOIN
    indirect_attribution
      ON indirect_attribution.id_lead_ebdb = att.id_lead_ebdb
  WHERE
    indirect_attribution.id_lead_ebdb IS NULL
),
ranked_final AS (
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
    ROW_NUMBER() OVER (
      PARTITION BY final_attribution.id_lead_ebdb
      ORDER BY support_sessions.ts_created DESC
    ) AS rn
  FROM
    final_attribution
  LEFT JOIN
    support_sessions
      ON support_sessions.phone_number = final_attribution.phone_number
        AND support_sessions.ts_created <= final_attribution.ts_created
        AND support_sessions.ctwa_clid IS NOT NULL
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
FROM
  ranked_final
WHERE
  rn = 1
