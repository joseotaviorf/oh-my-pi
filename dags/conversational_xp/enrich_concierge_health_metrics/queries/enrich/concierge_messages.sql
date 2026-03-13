WITH base_outbound_notifications AS (
  SELECT DISTINCT
    un.id_user,
    m1.id_session AS id_copilot_session,
    s.id_external AS id_langfuse_session,
    un.destination AS user_phone,
    un.ts_sent AS ts_concierge_contact,
    m2.ts_created AS ts_message_sent,
    CASE
      WHEN un.action ILIKE '%medium%' THEN 'Medium intent'
      WHEN un.action ILIKE '%high%' THEN 'High intent'
      WHEN un.action ILIKE '%qualified%' THEN 'Qualified low intent'
      WHEN un.action ILIKE '%low%' THEN 'Unqualified low intent'
      WHEN un.action = 'ConciergeTriggerRetargeting' THEN 'Retargeting'
      WHEN un.action LIKE 'ConciergeContactSubmissionClassifieds%' AND CAST(un.payload AS STRING) LIKE '%Chaves%' THEN 'Classifieds - Chaves na mão'
      WHEN un.action LIKE 'ConciergeContactSubmissionClassifieds%' THEN 'Classifieds'
      WHEN un.action LIKE 'ConciergeContactSubmissionTtc%' THEN 'TTC Outbound'
      ELSE 'Undefined'
    END AS concierge_flow_type,
    m2.role AS message_author,
    m2.media_type = 'audio/ogg' AS has_audio,
    'outbound' AS concierge_flow
  FROM datalake_jaiminho_clean.user_notifications un
  LEFT JOIN datalake_copilot_service_clean.message m1 -- gets the outbound template message
    ON m1.id_external = un.id_entity
  LEFT JOIN datalake_copilot_service_clean.message m2 -- gets all the messages of the session
    ON m1.id_session = m2.id_session
  LEFT JOIN datalake_copilot_service_clean.session s 
    ON m1.id_session = s.id
  WHERE un.channel = 'whatsapp'
    AND un.action ILIKE '%concierge%'
    AND un.action NOT ILIKE '%refinement%'
    AND un.action NOT ILIKE '%carousel%'
    AND un.action NOT ILIKE '%cancelation%'
    AND un.action NOT ILIKE '%optout%'
    AND un.status IN ('delivered', 'read')
)

, base_inbound_messages AS (
  SELECT DISTINCT
    s.id_user,
    m.id_session AS id_copilot_session,
    s.id_external AS id_langfuse_session,
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
    m.role AS message_author,
    m.media_type = 'audio/ogg' AS has_audio,
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
)

, first_outbound_message AS (
  SELECT 
    user_phone,
    MIN(ts_concierge_contact) AS ts_first_outbound_contact
  FROM base_outbound_notifications
  GROUP BY user_phone
)

, first_inbound_message AS (
  SELECT 
    user_phone,
    MIN(ts_concierge_contact) AS ts_first_inbound_contact
  FROM base_inbound_messages
  GROUP BY user_phone
)

, outbound_human_reply AS (
  SELECT
    user_phone,
    id_copilot_session,
    TRUE AS has_human_reply,
    MAX(has_audio) AS has_audio,
    COUNT(*) AS n_human_replies,
    COUNT_IF(has_audio) AS n_audio_replies
  FROM base_outbound_notifications
  WHERE ts_concierge_contact BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_7}) AND DATE('{end_date}')
    AND message_author = 'HUMAN'
  GROUP BY ALL
)

, inbound_human_reply AS (
  SELECT
    user_phone,
    id_copilot_session,
    TRUE AS has_human_reply,
    MAX(has_audio) AS has_audio,
    COUNT(*) AS n_human_replies,
    COUNT_IF(has_audio) AS n_audio_replies
  FROM base_inbound_messages
  WHERE ts_concierge_contact BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_7}) AND DATE('{end_date}')
    AND message_author = 'HUMAN'
  GROUP BY ALL
)

, in_outbound_users AS (
  SELECT DISTINCT
    bon.id_user,
    bon.id_copilot_session,
    bon.id_langfuse_session,
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
    ON bon.user_phone = ohr.user_phone
    AND bon.id_copilot_session = ohr.id_copilot_session
  WHERE bon.ts_concierge_contact BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_7}) AND DATE('{end_date}')

  UNION ALL

  SELECT DISTINCT
    bin.id_user,
    bin.id_copilot_session,
    bin.id_langfuse_session,
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
    ON bin.user_phone = ihr.user_phone
    AND bin.id_copilot_session = ihr.id_copilot_session
  WHERE bin.ts_concierge_contact BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_7}) AND DATE('{end_date}')
)

, phone2user AS (
  SELECT DISTINCT
    cr.id_reference AS id_user,
    ci.contact_info AS phone
  FROM datalake_person_clean.credential_reference cr
  JOIN datalake_person_clean.contact_info ci
    ON ci.id_person = cr.id_person
  WHERE ci.category = 'PHONE'
)

SELECT DISTINCT
  CASE
    WHEN iou.id_user = 0 OR iou.id_user IS NULL THEN p2u.id_user
    ELSE iou.id_user
  END AS id_user,
  iou.id_copilot_session,
  iou.id_langfuse_session,
  iou.user_phone,
  MD5(CONCAT(iou.user_phone, '-', iou.id_copilot_session)) AS id_phone_session,
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
LEFT JOIN phone2user p2u
  ON iou.user_phone = p2u.phone