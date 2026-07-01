WITH bianca_signal_actions AS (
  -- A1: greeting with property context → BiancaFollowupVisitSeeker
  SELECT 'greeting_context'              AS trigger_type, 'BiancaWelcomeContextSeeker_whatsapp_message'          AS action
  UNION ALL
  -- A2, D1: generic greeting (no property/filter context) → BiancaFollowupSeeker
  SELECT 'greeting_generic',                              'BiancaWelcomeSeekerTest_whatsapp_message'
  UNION ALL
  -- D2: greeting with saved search filters → BiancaFollowupFiltersSeeker
  SELECT 'greeting_filters',                              'BiancaWelcomeFiltersSeeker_whatsapp_message'
  UNION ALL
  -- B1: confirm contact (agency), first-time user → BiancaFollowupVisitConfirmSeeker
  SELECT 'confirm_contact',                               'BiancaConfirmDataSeeker_whatsapp_message'
  UNION ALL
  -- B2: confirm contact (agency), returning user (ToS already accepted) → BiancaFollowupVisitConfirm2Seeker
  SELECT 'confirm_contact_returning',                     'BiancaConfirmDataTycSeeker_whatsapp_message'
  UNION ALL
  -- C1, C2: confirm contact (pre-schedule visit) → BiancaFollowupScheduleVisitSeeker
  SELECT 'confirm_contact_visit',                         'BiancaConfirmDataVisitSeeker_whatsapp_message'
  UNION ALL
  SELECT 'confirm_contact_visit',                         'BiancaConfirmDataVisitTycSeeker_whatsapp_message'
  UNION ALL
  -- E1: after property recommendations carousel → BiancaFollowupRecSeeker
  SELECT 'after_recommendations',                         'biancaImovelwebRecsCarousel_whatsapp_message_carousel'
),

conv_tails AS (
  SELECT
    m.id_session,
    m.id_external,
    m.role,
    m.ts_created AS tail_timestamp,
    ROW_NUMBER() OVER (
      PARTITION BY m.id_session
      ORDER BY m.ts_created DESC
    ) AS rownum
  FROM datalake_copilot_service_clean.message m
  WHERE m.channel IN ('WHATSAPP_BIANCA_CHAT', 'WHATSAPP_CONCIERGE_CHAT')
    AND datediff(current_date, DATE(m.ts_created)) <= 60
),

candidates AS (
  SELECT
    md5(concat(un.destination, '|', bsa.trigger_type, '|', cast(ct.tail_timestamp AS STRING))) AS id,
    un.destination AS phone_number,
    bsa.trigger_type,
    ct.tail_timestamp AS signal_timestamp,
    current_timestamp() AS created_at,
    YEAR(current_date()) AS year,
    MONTH(current_date()) AS month,
    DAY(current_date()) AS day
  FROM datalake_jaiminho_clean.user_notifications un
  INNER JOIN conv_tails ct
    ON un.id_entity = ct.id_external
  INNER JOIN bianca_signal_actions bsa
    ON un.action = bsa.action
  WHERE UPPER(un.channel) = 'WHATSAPP'
    AND UPPER(un.status) IN ('READ', 'SENT', 'DELIVERED')
    AND datediff(current_date, make_date(un.year, un.month, un.day)) <= 60
    AND un.destination IS NOT NULL
    AND ct.id_session IS NOT NULL
    AND ct.rownum = 1
    AND ct.role IN ('AI', 'HARDCODED')
    AND ct.tail_timestamp <= current_timestamp() - INTERVAL 24 HOURS
)

SELECT
  id,
  phone_number,
  trigger_type,
  signal_timestamp,
  created_at,
  year,
  month,
  day
FROM candidates
