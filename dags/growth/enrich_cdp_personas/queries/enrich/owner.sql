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
    MAX(COALESCE(ts_next_user_event, ts_first_user_event)) AS ts_last_user_event
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
      AND h.status <> 'excluido'
),
finding_gaps AS (
SELECT
  id_house,
  id_user,
  SUM(
    CASE 
      WHEN ts_first_user_event > COALESCE(
          MAX(COALESCE(ts_last_user_event, NOW() + INTERVAL '1 years')) OVER (
        PARTITION BY id_user 
        ORDER BY ts_first_user_event 
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ), NOW() + INTERVAL '1 years'
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
),
contract_person_history AS (
  -- Building historical timeline for owners in contract_person using audit table
  SELECT
    cp.id_contract,
    cp.id_user,
    MIN(ure.ts_revision) AS ts_first_user_event,
    LEAD(MIN(ure.ts_revision)) OVER (PARTITION BY cp.id_contract, cp.id_user ORDER BY MIN(ure.ts_revision)) AS ts_next_user_event,
    cp.rev_type
  FROM
    datalake_ebdb_clean.contract_person_aud AS cp
  JOIN
    datalake_ebdb_user.user_revision_entity AS ure
      ON ure.id = cp.rev
  WHERE
    cp.type = 'Proprietario'
    AND cp.id_user IS NOT NULL
  GROUP BY cp.id_contract, cp.id_user, cp.rev_type
),
adjusting_contract_person_history AS (
  -- If rev_type = 2 (DELETE), use the timestamp as the last event
  SELECT
    id_contract,
    id_user,
    ts_first_user_event,
    IF(rev_type = 2, ts_first_user_event, ts_next_user_event) AS ts_next_user_event
  FROM
    contract_person_history
),
contract_owners_base AS (
  -- Consolidate periods per contract first
  SELECT
    id_contract,
    id_user,
    MIN(ts_first_user_event) AS ts_first_user_event,
    MAX(COALESCE(ts_next_user_event, ts_first_user_event)) AS ts_last_user_event
  FROM
    adjusting_contract_person_history
  GROUP BY id_contract, id_user
),
current_contract_owners AS (
  -- Identify which owners are currently associated with each contract
  SELECT DISTINCT
    id_contract,
    id_user
  FROM
    datalake_ebdb_clean.contract_person
  WHERE
    type = 'Proprietario'
),
contract_end_dates AS (
  -- Get contract end dates for inactive contracts
  SELECT
    id_contract,
    status,
    COALESCE(dt_termination, ts_updated) AS ts_contract_end
  FROM
    core_contract.contract
  WHERE
    status IN ('Finalizado', 'Cancelado')
),
adjusting_contract_owners_base AS (
  -- Adjust last timestamp based on contract status and owner presence
  -- Only use contract end date if owner is still associated when contract ends
  SELECT
    co.id_contract,
    co.id_user,
    co.ts_first_user_event,
    CASE
      -- Contract is active and owner is still in it
      WHEN ced.id_contract IS NULL AND cco.id_user IS NOT NULL THEN NULL
      -- Contract is inactive, owner is still associated, and only 1 revision
      WHEN ced.id_contract IS NOT NULL 
        AND cco.id_user IS NOT NULL 
        AND co.ts_first_user_event = co.ts_last_user_event 
      THEN ced.ts_contract_end
      -- Otherwise use the audit timestamp
      ELSE co.ts_last_user_event
    END AS ts_last_user_event
  FROM
    contract_owners_base AS co
  LEFT JOIN
    current_contract_owners AS cco
      ON cco.id_contract = co.id_contract
      AND cco.id_user = co.id_user
  LEFT JOIN
    contract_end_dates AS ced
      ON ced.id_contract = co.id_contract
),
contract_owners_consolidated AS (
  -- Remove id_contract and consolidate by user
  SELECT
    id_user,
    ts_first_user_event,
    ts_last_user_event
  FROM
    adjusting_contract_owners_base
),
finding_gaps_contract AS (
  SELECT
    id_user,
    SUM(
      CASE 
        WHEN ts_first_user_event > COALESCE(
            MAX(COALESCE(ts_last_user_event, NOW() + INTERVAL '1 years')) OVER (
          PARTITION BY id_user 
          ORDER BY ts_first_user_event 
          ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
          ), NOW() + INTERVAL '1 years'
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
    contract_owners_consolidated
),
groupping_gaps_contract AS (
  SELECT 
    id_user,
    MIN(ts_first_user_event) AS ts_first_event,
    CASE 
      WHEN COUNT(*) > COUNT(ts_last_user_event) THEN NULL
      ELSE MAX(ts_last_user_event)
    END AS ts_last_event
  FROM
    finding_gaps_contract
  GROUP BY id_user, id_group
),
unioned_owners AS (
  -- Union intervals from both sources (house + contract).
  -- Next step will reconcile/merge intervals into a single timeline per user.
  SELECT
    id_user,
    ts_first_event,
    ts_last_event
  FROM
    groupping_gaps
  UNION ALL
  SELECT
    id_user,
    ts_first_event,
    ts_last_event
  FROM
    groupping_gaps_contract
),
finding_gaps_combined AS (
  -- Re-run the "gap finding" logic on the unioned timeline, to merge overlapping periods
  -- (including open-ended intervals where ts_last_event IS NULL).
  SELECT
    id_user,
    SUM(
      CASE
        WHEN ts_first_event > COALESCE(
            MAX(COALESCE(ts_last_event, NOW() + INTERVAL '1 years')) OVER (
              PARTITION BY id_user
              ORDER BY ts_first_event
              ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ),
            NOW() + INTERVAL '1 years'
          )
        THEN 1
        ELSE 0
      END
    ) OVER (
      PARTITION BY id_user
      ORDER BY ts_first_event
    ) AS id_group,
    ts_first_event,
    ts_last_event
  FROM
    unioned_owners
),
groupping_gaps_combined AS (
  SELECT
    id_user,
    MIN(ts_first_event) AS ts_first_event,
    CASE
      WHEN COUNT(*) > COUNT(ts_last_event) THEN NULL
      ELSE MAX(ts_last_event)
    END AS ts_last_event
  FROM
    finding_gaps_combined
  GROUP BY
    id_user,
    id_group
)
SELECT DISTINCT
  co.id_user,
  u.uuid_person,
  IF(co.ts_last_event IS NULL, TRUE, FALSE) AS is_active,
  co.ts_first_event,
  co.ts_last_event,
  NOW() AS ts_load
FROM
  groupping_gaps_combined AS co
LEFT JOIN
  datalake_ebdb_clean.user AS u
    ON u.id = co.id_user