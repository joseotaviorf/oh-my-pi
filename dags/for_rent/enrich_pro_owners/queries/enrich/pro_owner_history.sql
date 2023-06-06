WITH aud_ts AS (
  SELECT /*+ RANGE_JOIN(aud, 50000) */
    COALESCE(um2.id_winner_account, um.id_winner_account, aud.id_user) AS id_owner,
    LAG(aud.id_account_manager) OVER (PARTITION BY COALESCE(um2.id_winner_account, um.id_winner_account, aud.id_user) ORDER BY aud.rev) AS id_previous_account_manager,
    aud.id_account_manager,
    LAG(aud.is_active) OVER (PARTITION BY COALESCE(um2.id_winner_account, um.id_winner_account, aud.id_user) ORDER BY aud.rev) AS previous_status,
    aud.is_active,
    TIMESTAMP(FROM_UNIXTIME(ure.ts_revision/1000)) AS ts_event
  FROM 
    datalake_ebdb_clean.user_pro_owner_aud AS aud
  JOIN 
    datalake_ebdb_clean.user_revision_entity AS ure 
      ON aud.rev = ure.id
  LEFT JOIN
    datalake_ebdb_clean.user_merge AS um
      ON aud.id_user = um.id_loser_account
      AND um.status = 'MERGED'
  LEFT JOIN
    datalake_ebdb_clean.user_merge AS um2
      ON um.id_winner_account = um2.id_loser_account
      AND um2.status = 'MERGED'
),

pro_owner_dates AS (
  SELECT 
    aud.id_owner,
    aud.is_active,
    aud.ts_event AS ts_pro_owner_started,
    LEAD(aud.ts_event) OVER (PARTITION BY aud.id_owner ORDER BY aud.ts_event) AS ts_pro_owner_ended
  FROM 
    aud_ts AS aud
  WHERE 
      aud.previous_status != aud.is_active
      OR aud.previous_status IS NULL
),

account_manager_dates AS (
  SELECT 
    aud.id_owner,
    aud.id_account_manager,
    aud.is_active,
    aud.ts_event AS ts_account_manager_started,
    LEAD(aud.ts_event) OVER (PARTITION BY aud.id_owner ORDER BY aud.ts_event) AS ts_account_manager_ended
  FROM 
    aud_ts AS aud
  WHERE
    (aud.id_previous_account_manager != aud.id_account_manager
    OR aud.id_previous_account_manager IS NULL
    OR aud.previous_status != aud.is_active)
)

SELECT
  at.id_owner,
  CASE 
    WHEN at.is_active = False THEN NULL
    ELSE at.id_account_manager
  END AS id_account_manager,
  at.is_active AS is_pro_owner,
  CASE
    WHEN at.is_active = False 
      OR at.id_account_manager IS NULL THEN False
    ELSE True
  END AS is_expert,
  at.ts_event,
  pod.ts_pro_owner_started,
  pod.ts_pro_owner_ended,
  am.ts_account_manager_started,
  am.ts_account_manager_ended
FROM 
  aud_ts AS at
LEFT JOIN 
  pro_owner_dates AS pod
    ON at.id_owner = pod.id_owner
    AND at.ts_event >= pod.ts_pro_owner_started
    AND at.ts_event < COALESCE(pod.ts_pro_owner_ended, CURRENT_TIMESTAMP())
    AND pod.is_active = True
LEFT JOIN 
  account_manager_dates AS am
    ON at.id_owner = am.id_owner
    AND at.id_account_manager = am.id_account_manager
    AND at.ts_event >= am.ts_account_manager_started 
    AND at.ts_event < COALESCE(am.ts_account_manager_ended, CURRENT_TIMESTAMP())
    AND am.is_active = True