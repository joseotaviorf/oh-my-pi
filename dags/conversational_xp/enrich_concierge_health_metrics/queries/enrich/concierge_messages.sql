WITH concierge_trigger AS (
  SELECT DISTINCT
    CASE
      WHEN intent LIKE 'medium_reprocess%' THEN 'Medium FUP'
      WHEN intent LIKE 'medium_fup%' THEN 'Medium FUP'
      WHEN intent LIKE 'visit_cancellation_fup%' THEN 'Visit cancellation FUP'
      WHEN intent LIKE '%favorites%' THEN 'Favorites'
      ELSE intent
    END AS trigger_intent,
    uuid_trigger_id
  FROM datalake_house_listing_search_clean.concierge_trigger
  WHERE 
    DATE(ts_created) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
    AND outcome = 'SUCCESS'
    AND chatbot = 'JULIA'
)

, base_outbound_notifications AS (
  SELECT
    un.id_user,
    m.id_session AS id_copilot_session,
    s.id_external AS id_langfuse_session,
    un.id AS id_notification,
    m.id AS id_message,
    un.destination AS user_phone,
    un.ts_sent AS ts_concierge_contact,
    m.ts_created AS ts_message_sent,
    CASE
      WHEN un.action ILIKE '%medium%' THEN 'Medium intent'
      WHEN un.action ILIKE '%high%' THEN 'High intent'
      WHEN un.action ILIKE '%qualified%' THEN 'Qualified low intent'
      WHEN un.action ILIKE '%low%' THEN 'Unqualified low intent'
      WHEN un.action = 'ConciergeTriggerRetargeting' THEN 'Retargeting'
      WHEN un.action LIKE 'ConciergeContactSubmissionClassifieds%' AND CAST(un.payload AS STRING) LIKE '%Chaves%' THEN 'Classifieds - Chaves na mão'
      WHEN un.action LIKE 'ConciergeContactSubmissionClassifieds%' THEN 'Classifieds'
      WHEN un.action LIKE 'ConciergeContactSubmissionTtcQac%' THEN 'TTC QAC Outbound'
      WHEN un.action LIKE 'ConciergeContactSubmissionTtc%' THEN 'TTC Outbound'
      WHEN un.action = 'ConciergeOutboundNotification_whatsapp' AND un.template IN ('concierge_placas_agents_reproc_trigger', 'concierge_placas_reply_sfmc') THEN 'Placas agent FUP'
      WHEN un.action = 'ConciergeOutboundNotification_whatsapp' THEN COALESCE(t.trigger_intent, 'Undefined')
    ELSE 'Undefined'
    END AS concierge_flow_type,
    'outbound' AS concierge_flow
  FROM datalake_jaiminho_clean.user_notifications un
  LEFT JOIN datalake_copilot_service_clean.message m -- gets the outbound template message
    ON m.id_external = un.id_entity
  LEFT JOIN concierge_trigger t
    ON m.id_idempotency = t.uuid_trigger_id
  LEFT JOIN datalake_copilot_service_clean.session s 
    ON m.id_session = s.id
  WHERE un.channel = 'whatsapp'
    AND un.action ILIKE '%concierge%'
    AND un.action NOT ILIKE '%refinement%'
    AND un.action NOT ILIKE '%carousel%'
    AND un.action NOT ILIKE '%cancelation%'
    AND un.action NOT ILIKE '%optout%'
    AND un.action <> 'ConciergeSharedLpvAdsTrigger'
    AND un.action NOT LIKE 'ConciergeSendLeadConfirmation_whatsapp_message%'
    AND un.status IN ('delivered', 'read')
    AND MAKE_DATE(un.year, un.month, un.day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
)

, base_inbound_messages AS (
  SELECT
    s.id_user,
    m.id_session AS id_copilot_session,
    s.id_external AS id_langfuse_session,
    m.id AS id_message,
    ss.user_phone,
    s.ts_created AS ts_concierge_contact,
    m.ts_created AS ts_message_sent,
    CASE
      WHEN m.content ILIKE '%plaquinhas_qrwhats%' OR m.content LIKE '%quin.to/perto-placas-quero-%' THEN 'Placas'
      WHEN m.content LIKE '%site=IWBR%' THEN 'Imovel web'
      WHEN m.content ILIKE '%chaves na mão%' THEN 'Chaves na mão'
      WHEN m.content LIKE 'Código do imóvel: 8%' THEN 'TTC'
      WHEN m.content LIKE 'Olá! Gostaria de ver alguns imóveis no QuintoAndar. Você pode me ajudar?' THEN 'Click2WPP'
      WHEN m.content ILIKE 'conferir disponibilidade' OR m.content = 'Sim, ver imóveis' THEN 'Automatic reply to previous message'
      ELSE 'Freeform'
    END AS concierge_flow_type,
    'inbound' AS concierge_flow
  FROM datalake_copilot_service_clean.message m
  LEFT JOIN datalake_copilot_service_clean.session s
    ON m.id_session = s.id
  LEFT JOIN datalake_sauron_clean.session ss
    ON s.id_sauron_session = ss.id
  WHERE m.channel = 'WHATSAPP_CONCIERGE_CHAT'
    AND (
      m.content ILIKE '%plaquinhas_qrwhats%'
      OR m.content LIKE '%quin.to/perto-placas-quero-%'
      OR m.content LIKE '%site=IWBR%'
      OR m.content ILIKE '%chaves na mão%'
      OR m.content LIKE 'Código do imóvel: 8%'
      OR m.content LIKE 'Olá! Gostaria de ver alguns imóveis no QuintoAndar. Você pode me ajudar?'
      OR (m.message_index = 0 AND m.role = 'HUMAN')
    )
    AND m.content IS DISTINCT FROM 'Pausar recomendações' -- IS DISTINCT FROM includes nulls. It's important to include them as they usually are midia content (e.g. image) and can have direct VB associated.
    AND m.ts_created BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
)

, first_outbound_message AS (
    SELECT
        user_phone,
        MIN(ts_first_outbound_contact) AS ts_first_outbound_contact
    FROM (
      -- gets the first time of contact of current incremental scan
        SELECT 
          user_phone, 
          MIN(ts_concierge_contact) AS ts_first_outbound_contact
        FROM base_outbound_notifications
        GROUP BY user_phone
        UNION ALL
        -- gets the first time of contact saved in the table. To get it correct, the first run of this table must be from 2025/07/01 (concierge roll out)
        SELECT 
          user_phone, 
          MIN(ts_first_outbound_contact) AS ts_first_outbound_contact
        FROM datalake_search.concierge_messages
        WHERE ts_first_outbound_contact IS NOT NULL
        GROUP BY user_phone
    )
    GROUP BY user_phone
)

, first_inbound_message AS (
    SELECT
        user_phone,
        MIN(ts_first_inbound_contact) AS ts_first_inbound_contact
    FROM (
        -- gets the first time of contact of current incremental scan
        SELECT 
          user_phone, 
          MIN(ts_concierge_contact) AS ts_first_inbound_contact
        FROM base_inbound_messages
        GROUP BY user_phone
        UNION ALL
        -- gets the first time of contact saved in the table
        SELECT 
          user_phone, 
          MIN(ts_first_inbound_contact) AS ts_first_inbound_contact
        FROM datalake_search.concierge_messages
        WHERE ts_first_inbound_contact IS NOT NULL
        GROUP BY user_phone
    )
    GROUP BY user_phone
)

, outbound_human_reply AS (
  SELECT
    o.id_notification,
    o.id_copilot_session,
    TRUE AS has_human_reply,
    MAX(m.media_type = 'audio/ogg') AS has_audio,
    COUNT(*) AS n_human_replies,
    COUNT_IF(m.media_type = 'audio/ogg') AS n_audio_replies
  FROM base_outbound_notifications o
  JOIN datalake_copilot_service_clean.message m -- gets all the messages of the session
     ON o.id_copilot_session = m.id_session
     AND m.ts_created >= o.ts_message_sent
     AND m.role = 'HUMAN'
  GROUP BY
    o.id_notification,
    o.id_copilot_session
)

, inbound_human_reply AS (
  SELECT
    i.id_message,
    i.id_copilot_session,
    TRUE AS has_human_reply,
    MAX(m.media_type = 'audio/ogg') AS has_audio,
    COUNT(*) AS n_human_replies,
    COUNT_IF(m.media_type = 'audio/ogg') AS n_audio_replies
  FROM base_inbound_messages i
  JOIN datalake_copilot_service_clean.message m 
     ON i.id_copilot_session = m.id_session
     AND m.role = 'HUMAN'
  GROUP BY
    i.id_message,
    i.id_copilot_session
)

, in_outbound_users AS (
  SELECT 
    bon.id_user,
    bon.id_copilot_session,
    bon.id_langfuse_session,
    bon.id_notification,
    bon.id_message,
    bon.user_phone,
    bon.ts_concierge_contact,
    bon.ts_message_sent,
    bon.concierge_flow_type,
    COALESCE(ohr.has_human_reply, FALSE) AS has_human_reply,
    COALESCE(ohr.has_audio, FALSE) AS has_audio,
    COALESCE(ohr.n_human_replies, 0) AS n_human_replies,
    COALESCE(ohr.n_audio_replies, 0) AS n_audio_replies,
    bon.concierge_flow
  FROM base_outbound_notifications bon
  LEFT JOIN outbound_human_reply ohr
    ON bon.id_notification = ohr.id_notification

  UNION ALL

  SELECT 
    bin.id_user,
    bin.id_copilot_session,
    bin.id_langfuse_session,
    CAST(-1 AS BIGINT) AS id_notification,
    bin.id_message,
    bin.user_phone,
    bin.ts_concierge_contact,
    bin.ts_message_sent,
    bin.concierge_flow_type,
    COALESCE(ihr.has_human_reply, FALSE) AS has_human_reply,
    COALESCE(ihr.has_audio, FALSE) AS has_audio,
    COALESCE(ihr.n_human_replies, 0) AS n_human_replies,
    COALESCE(ihr.n_audio_replies, 0) AS n_audio_replies,
    bin.concierge_flow
  FROM base_inbound_messages bin
  LEFT JOIN inbound_human_reply ihr
    ON bin.id_message = ihr.id_message
)

SELECT
  COALESCE(NULLIF(NULLIF(iou.id_user, 0), -1),-1) AS id_user,
  iou.id_copilot_session,
  iou.id_langfuse_session,
  COALESCE(iou.id_notification, CAST(-1 AS BIGINT)) AS id_notification,
  COALESCE(iou.id_message, CAST(-1 AS BIGINT)) AS id_message,
  MD5(CONCAT(iou.user_phone, '-', iou.id_copilot_session)) AS id_phone_session,
  iou.user_phone,
  iou.concierge_flow,
  iou.concierge_flow_type,
  iou.has_human_reply,
  iou.has_audio,
  iou.n_human_replies,
  iou.n_audio_replies,
  iou.ts_concierge_contact,
  iou.ts_message_sent,
  fom.ts_first_outbound_contact,
  fim.ts_first_inbound_contact,
  LEAST(fom.ts_first_outbound_contact, fim.ts_first_inbound_contact) AS ts_first_concierge_contact,
  YEAR(iou.ts_concierge_contact) AS year,
  MONTH(iou.ts_concierge_contact) AS month,
  DAY(iou.ts_concierge_contact) AS day
FROM in_outbound_users iou
LEFT JOIN first_outbound_message fom
  ON iou.user_phone = fom.user_phone
LEFT JOIN first_inbound_message fim
  ON iou.user_phone = fim.user_phone
