WITH agents AS (
  SELECT
    u.id_main_user
  FROM
    datalake_hub_services.users AS u
  JOIN
    datalake_hub_services.member_profile AS mp
      ON mp.id_user = u.id_user
      AND mp.profile = 'AGENT'
)
SELECT
  m.id_channel,
  m.id_message,
  m.id_user_external,
  CASE
    WHEN LAG(m.id_user_external) OVER(PARTITION BY m.id_channel ORDER BY m.ts_created) != m.id_user_external THEN 1
    ELSE 0
  END AS changed_turn,
  CASE
    WHEN a.id_main_user IS NOT NULL THEN 'AGENT'
    ELSE 'PROSPECT'
  END AS user_role,
  m.chat_type,
  m.message,
  m.index,
  m.ts_created,
  LAG(m.ts_created) OVER(PARTITION BY m.id_channel ORDER BY m.ts_created) AS ts_last_message
FROM
  datalake_internal_chat_clean.internal_chat_messages AS m
LEFT JOIN
  agents AS a
    ON a.id_main_user = m.id_user_external
WHERE
  m.chat_type = "QuintoandarPrivate"
  AND MAKE_DATE(m.year, m.month, m.day) BETWEEN "{load_start_date}" AND "{load_end_date}"
