WITH house_status AS (
  -- Checking the user's first and last event on a property based on status
  SELECT
    h.id_house,
    h.id_user,
    h.status,
    MIN(ts_revision) AS ts_first_user_event,
    LEAD(MIN(ts_revision)) OVER (PARTITION BY h.id_house ORDER BY MIN(ts_revision)) AS ts_next_user_event
  FROM
    datalake_ebdb_clean.house_aud AS h
  JOIN
    datalake_ebdb_user.user_revision_entity AS ure
      ON ure.id = h.rev
  WHERE
    h.id_user IS NOT NULL
  GROUP BY 1, 2, 3
),
adjusting_house_status AS (
  -- If the tuple [id_house, id_user] has any 'excluido' status, it's necessary to account this timestamp 
  -- as the last user event
  SELECT
    id_house,
    id_user,
    status,
    ts_first_user_event,
    IF(status = 'excluido', ts_first_user_event, ts_next_user_event) AS ts_next_user_event
  FROM
    house_status
),
owners_base AS (
  SELECT
    id_house,
    id_user,
    MIN(ts_first_user_event) AS ts_first_user_event,
    MAX(ts_next_user_event) AS ts_last_user_event
  FROM
    adjusting_house_status
  GROUP BY 1, 2
),
adjusting_owners_base AS (
  -- If the the tuple [id_house, id_user] is active, the last timestamp must be null
  SELECT
    o.id_house,
    o.id_user,
    o.ts_first_user_event,
    IF(h.id IS NOT NULL, NULL, o.ts_last_user_event) AS ts_last_user_event
  FROM
    owners_base AS o
  LEFT JOIN
    datalake_ebdb_clean.house AS h
      ON h.id = o.id_house
      AND h.id_user = o.id_user
),
finding_gaps AS (
SELECT
  id_house,
  id_user,
  SUM(
    CASE 
      WHEN ts_first_user_event > MAX(ts_last_user_event) OVER (
        PARTITION BY id_user 
        ORDER BY ts_first_user_event 
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
      ) THEN 1 
      ELSE 0 
    END
  ) OVER (
    PARTITION BY id_user 
    ORDER BY ts_first_user_event
  ) AS id_group,
  ts_first_user_event,
  ts_last_user_event
FROM
  adjusting_owners_base
),
groupping_gaps AS (
  SELECT 
    id_user,
    MIN(ts_first_user_event) AS ts_first_event,
    CASE 
      WHEN COUNT(*) > COUNT(ts_last_user_event) THEN NULL
      ELSE MAX(ts_last_user_event)
    END AS ts_last_event
  FROM
    finding_gaps 
  GROUP BY id_user, id_group
)
SELECT DISTINCT
  gg.id_user,
  u.uuid_person,
  IF(ts_last_event IS NULL, TRUE, FALSE) AS is_active,
  ts_first_event,
  ts_last_event,
  NOW() AS ts_load
FROM
  groupping_gaps AS gg
LEFT JOIN
  datalake_ebdb_clean.user AS u
    ON u.id = gg.id_user