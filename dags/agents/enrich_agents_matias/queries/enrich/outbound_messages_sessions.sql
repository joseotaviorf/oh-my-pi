WITH jaiminho_notifications AS (
  SELECT
    id,
    id_user,
    channel,
    status,
    template,
    COALESCE(ts_sent, ts_created) AS ts_notification_sent,
    ts_created,
    year,
    month,
    day
  FROM
    datalake_jaiminho_clean.notifications
  WHERE
    channel = 'whatsapp'
    AND GET_JSON_OBJECT(payload, '$.waent_env') = 'corretores_relacionamento'
    AND month BETWEEN 1 AND 12
    AND day BETWEEN 1 AND 31
    AND MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
dominic_sessions AS (
  SELECT
    id_session,
    id_sauron_session,
    id_langfuse_session,
    id_user,
    ts_created,
    ts_updated,
    is_escalated
  FROM
    datalake_chatbot.sessions
  WHERE
    bot = 'dominic'
    AND ts_updated >= '{load_start_date}'
),
joined AS (
  SELECT
    n.id AS id_notification,
    n.id_user,
    n.channel,
    n.status,
    n.template,
    n.ts_notification_sent,
    s.id_sauron_session,
    s.id_session AS id_chatbot_session,
    s.id_langfuse_session,
    s.id_sauron_session IS NOT NULL AS has_matched_session,
    s.is_escalated,
    s.ts_created AS ts_session_created,
    s.ts_updated AS ts_session_updated,
    YEAR(n.ts_notification_sent) AS year,
    MONTH(n.ts_notification_sent) AS month,
    DAY(n.ts_notification_sent) AS day,
    ROW_NUMBER() OVER (
      PARTITION BY n.id
      ORDER BY s.ts_updated DESC NULLS LAST
    ) AS rn
  FROM
    jaiminho_notifications AS n
  LEFT JOIN
    dominic_sessions AS s
      ON CAST(n.id_user AS STRING) = CAST(s.id_user AS STRING)
      AND s.ts_created > n.ts_notification_sent
      AND s.ts_created <= n.ts_notification_sent + INTERVAL 1 DAY
)
SELECT
  id_notification,
  id_user,
  channel,
  status,
  template,
  ts_notification_sent,
  id_sauron_session,
  id_chatbot_session,
  id_langfuse_session,
  has_matched_session,
  is_escalated,
  ts_session_created,
  ts_session_updated,
  year,
  month,
  day
FROM
  joined
WHERE
  rn = 1
