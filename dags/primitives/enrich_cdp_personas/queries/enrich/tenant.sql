WITH contract_status AS (
  SELECT
    c.id_contract,
    c.id_user,
    c.status,
    MIN(ts_revision) AS ts_first_event
  FROM
    datalake_ebdb_clean.contract_aud AS c
  JOIN
    datalake_ebdb_user.user_revision_entity AS ure
      ON ure.id = c.rev
  WHERE
    c.id_user IS NOT NULL -- Only contracts with users
  GROUP BY 1, 2, 3
),
ordering_contract_status AS (
  SELECT
    id_contract,
    id_user,
    status,
    LEAD(status) OVER (PARTITION BY id_contract ORDER BY ts_first_event) AS next_status,
    ts_first_event,
    LEAD(ts_first_event) OVER (PARTITION BY id_contract ORDER BY ts_first_event) AS ts_next_event
  FROM
    contract_status
),
tenants_base AS (
  -- Time window where the contract stayed as active
    SELECT
        id_user, 
        id_contract,
        MIN(ts_first_event) AS ts_first_active_event,
        MAX(ts_next_event) AS ts_last_active_event
    FROM
        ordering_contract_status
    WHERE
        status = 'Ativo'
    GROUP BY 1, 2
),
finding_gaps AS (
  -- Groupping contracts by active period (if more than one contract was active during the same period, it will be in the same id_group)
  SELECT
    t.id_user,
    t.id_contract,
    SUM(
      CASE
        WHEN ts_first_active_event > LAG(ts_last_active_event) OVER (
          PARTITION BY t.id_user
          ORDER BY
            ts_first_active_event
        ) THEN 1
       ELSE 0
      END
    ) OVER (
      PARTITION BY t.id_user ORDER BY ts_first_active_event
    ) AS id_group,
    ts_first_active_event,
    ts_last_active_event
    --IF(c.status = 'Ativo', NULL, ts_last_active_event) AS ts_last_active_event  -- check if it's necessary
  FROM
    tenants_base AS t
),
groupping_gaps AS (
  -- Getting the first active event inside an id_group and checking if the id_group can be marked as active til now
  -- if at least one of its contracts is still active
  SELECT 
    id_user,
    MIN(ts_first_active_event) AS ts_first_event,
    CASE 
      WHEN COUNT(*) > COUNT(ts_last_active_event) THEN NULL
      ELSE MAX(ts_last_active_event)
    END AS ts_last_event
  FROM
    finding_gaps 
  GROUP BY id_user, id_group
)
SELECT DISTINCT
  id_user,
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