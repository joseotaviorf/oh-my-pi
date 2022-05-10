WITH aud_ts AS (
  SELECT /*+ RANGE_JOIN(aud, 50000) */
    aud.id_user AS id_owner,
    aud.id_account_manager,
    aud.is_active,
    LAG(aud.id_account_manager) OVER (PARTITION BY aud.id_user ORDER BY aud.rev) AS previous_account_manager,
    LAG(aud.is_active) OVER (PARTITION BY aud.id_user ORDER BY aud.rev) AS previous_status,
    FROM_UNIXTIME(ure.ts_revision/1000) AS ts_event
  FROM 
    datalake_ebdb_clean.user_pro_owner_aud AS aud
  LEFT JOIN 
    datalake_ebdb_clean.user_revision_entity AS ure 
      ON aud.rev = ure.id
),
aud_events AS (
  SELECT 
    aud.id_owner,
    aud.id_account_manager,
    aud.is_active,
    aud.ts_event,
    LEAD(aud.ts_event, 1) OVER (PARTITION BY aud.id_owner  ORDER BY aud.ts_event) AS ts_next_event
  FROM 
    aud_ts AS aud
  WHERE
    NOT (COALESCE(id_account_manager, -1) = COALESCE(previous_account_manager, -1)
    AND COALESCE(is_active, false) = COALESCE(previous_status, false))
),
pro_owner_dates AS (
  SELECT 
    aud.id_owner,
    aud.is_active,
    aud.ts_event AS ts_pro_owner_started,
    MIN(aud_ts.ts_event) AS ts_pro_owner_ended
  FROM 
    aud_ts AS aud
  LEFT JOIN 
    aud_ts
      ON aud_ts.id_owner = aud.id_owner
      AND aud_ts.is_active != aud.is_active
      AND aud_ts.ts_event > aud.ts_event
  WHERE 
      aud.previous_status != aud.is_active
      OR aud.previous_status IS NULL
  GROUP BY 
    1,2,3
),
account_manager AS (
  SELECT 
    aud.id_owner,
    aud.id_account_manager,
    MIN(aud.ts_event) AS ts_account_manager_started,
    MIN(aud_ts.ts_event) AS ts_account_manager_ended
  FROM 
    aud_ts AS aud
  LEFT JOIN 
    aud_ts
      ON aud_ts.id_owner = aud.id_owner
      AND aud_ts.id_account_manager != aud.id_account_manager
      AND aud_ts.ts_event > aud.ts_event
  GROUP BY 
    1,2
)
SELECT DISTINCT
  at.id_owner,
  aud.id_account_manager,
  aud.is_active AS is_pro_owner,
  CASE
    WHEN aud.is_active = False 
      OR aud.id_account_manager IS NULL THEN False
    ELSE True
  END AS is_expert,
  aud.ts_event,
  pod.ts_pro_owner_started,
  pod.ts_pro_owner_ended,
  am.ts_account_manager_started,
  am.ts_account_manager_ended
FROM 
  aud_ts AS at
JOIN 
  aud_events AS aud
    ON at.id_owner = aud.id_owner
    AND at.ts_event >= aud.ts_event 
    AND at.ts_event < COALESCE(aud.ts_next_event, CURRENT_TIMESTAMP())
LEFT JOIN 
  pro_owner_dates AS pod
    ON at.id_owner = pod.id_owner
    AND aud.is_active = pod.is_active
    AND at.ts_event >= pod.ts_pro_owner_started
    AND at.ts_event < COALESCE(pod.ts_pro_owner_ended, CURRENT_TIMESTAMP())
LEFT JOIN 
  account_manager AS am
    ON at.id_owner = am.id_owner
    AND aud.id_account_manager = am.id_account_manager
    AND at.ts_event >= am.ts_account_manager_started 
    AND at.ts_event < COALESCE(am.ts_account_manager_ended, CURRENT_TIMESTAMP())
WHERE
  DATE(at.ts_event) <= DATE('{year}-{month}-{day}')