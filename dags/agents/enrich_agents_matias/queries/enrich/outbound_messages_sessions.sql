WITH comms_events AS (
  SELECT
    CAST(SPLIT(id_event, '-')[0] AS BIGINT) AS id_notification,
    CAST(NULLIF(TRIM(id_user), '') AS BIGINT) AS id_user,
    channel,
    comms_status AS status,
    comms_template AS template,
    CAST(
      FROM_UNIXTIME(
        CAST(GET_JSON_OBJECT(event_properties, '$.sentAt') AS BIGINT) / 1000
      ) AS TIMESTAMP
    ) AS ts_notification_sent,
    ts_event
  FROM
    datalake_cdp_clean.comms
  WHERE
    channel = 'whatsapp'
    AND event_name = 'notification_status_update'
    AND GET_JSON_OBJECT(event_properties, '$.destination.waentEnv') = 'corretores_relacionamento'
    AND month BETWEEN 1 AND 12
    AND day BETWEEN 1 AND 31
    AND MAKE_DATE(CAST(year AS INT), CAST(month AS INT), CAST(day AS INT))
      BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
comms_ranked AS (
  SELECT
    id_notification,
    MAX(id_user) OVER (PARTITION BY id_notification) AS id_user,
    channel,
    status,
    template,
    ts_notification_sent,
    ROW_NUMBER() OVER (
      PARTITION BY id_notification
      ORDER BY ts_event DESC
    ) AS rn_comms
  FROM
    comms_events
  WHERE
    id_notification IS NOT NULL
),
outbound_notifications AS (
  SELECT
    id_notification,
    id_user,
    channel,
    status,
    template,
    ts_notification_sent
  FROM
    comms_ranked
  WHERE
    rn_comms = 1
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
    n.id_notification,
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
      PARTITION BY n.id_notification
      ORDER BY s.ts_updated DESC NULLS LAST
    ) AS rn
  FROM
    outbound_notifications AS n
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
