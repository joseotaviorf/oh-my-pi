WITH actions AS (
  SELECT
    trh.id_task,
    COALESCE(CAST(trh.id_receiver AS BIGINT), -1) AS id_receiver,
    COALESCE(CAST(trh.id_origin AS BIGINT), -1) AS id_origin,
    COALESCE(CAST(trh.id_assignee AS BIGINT), -1) AS id_assignee,
    COALESCE(CAST(trh.id_user_action AS BIGINT), -1) AS id_user_action,
    COALESCE(trh.id_workgroup, -1) AS id_workgroup,
    COALESCE(CAST(DATE_FORMAT(ts_start, 'yyyyMMdd') AS BIGINT), -1) AS id_start_date,
    COALESCE(CAST(DATE_FORMAT(ts_action, 'yyyyMMdd') AS BIGINT), -1) AS id_action_date,
    COALESCE(CAST(DATE_FORMAT(ts_next_action, 'yyyyMMdd') AS BIGINT), -1) AS id_next_action_date,
    COALESCE(CAST(DATE_FORMAT(ts_completed, 'yyyyMMdd') AS BIGINT), -1) AS id_completed_date,
    trh.action_user_name,
    trh.action_type,
    trh.action_reason,
    trh.task_status,
    trh.type,
    ts_action,
    COALESCE(
        CAST(trh.task_user_resolve_hours AS DOUBLE),
        ROUND((
            TO_UNIX_TIMESTAMP(lead(trh.ts_action) OVER (PARTITION BY trh.id_task ORDER BY trh.ts_action), 'yyyy-MM-dd HH:mm:ss')
            - TO_UNIX_TIMESTAMP(trh.ts_action, 'yyyy-MM-dd HH:mm:ss')
        )/3600.0, 1)
    ) AS task_user_resolve_hours,
    trh.ts_action,
    trh.ts_next_action,
    year,
    month,
    day
  FROM
    datalake_crm_tasks_resolution.tasks_resolution_history trh
  WHERE 
    year = {year}
    AND month = {month}
    AND day = {day}
),
most_recent_completed_task_by_user AS (
  SELECT
    a.id_task,
    a.id_user_action,
    a.id_next_action_date,
    a.id_action_date,
    a.id_workgroup,
    a.type,
    a.action_type,
    a.task_user_resolve_hours,
    a.ts_next_action,
    a.ts_action,
    ROW_NUMBER() OVER (PARTITION BY a.id_task, a.id_user_action ORDER BY a.ts_action DESC) AS ranking
  FROM
    actions a
  WHERE
    a.action_type IN ('REALIZE', 'FINISH')
    AND a.id_user_action != -1
),
create_start_actions AS (
  SELECT
      id_task,
      MIN(CAST(CASE WHEN action_type = 'CREATE' THEN ts_action END AS TIMESTAMP)) AS ts_created_task,
      MIN(CAST(CASE WHEN action_type = 'START' THEN ts_action END AS TIMESTAMP)) AS ts_started_task
  FROM
      actions
  GROUP BY 1
),
tasks AS (
  SELECT DISTINCT
    a.id_task,
    a.id_receiver,
    a.id_origin,
    a.id_assignee,
    a.id_user_action,
    a.id_start_date,
    a.id_completed_date,
    COALESCE(mrbu.id_next_action_date, a.id_next_action_date) AS id_next_action_date,
    COALESCE(mrbu.id_action_date, a.id_action_date) AS id_action_date,
    a.id_workgroup,
    a.type,
    a.action_user_name,
    a.action_type,
    a.action_reason,
    a.task_status,
    ROUND(
      (TO_UNIX_TIMESTAMP(csa.ts_started_task, 'yyyy-MM-dd HH:mm:ss') - TO_UNIX_TIMESTAMP(csa.ts_created_task, 'yyyy-MM-dd HH:mm:ss'))/60.0,
      1
    ) AS minutes_task_created_to_started,
    COALESCE(mrbu.task_user_resolve_hours, a.task_user_resolve_hours) AS task_user_resolve_hours,
    COALESCE(mrbu.ts_next_action, a.ts_next_action) AS ts_next_action,
    COALESCE(mrbu.ts_action, a.ts_action) AS ts_action,
    DATE(CONCAT(year,'-',month,'-',day)) AS dt_partition,
    year,
    month,
    day
  FROM
      actions a
  LEFT JOIN
    create_start_actions csa
      ON a.id_task = csa.id_task
  LEFT JOIN
    most_recent_completed_task_by_user mrbu
      ON a.id_task = mrbu.id_task
      AND a.id_user_action = mrbu.id_user_action
      AND a.action_type = mrbu.action_type
      AND mrbu.ranking = 1
  WHERE
    -- due to a bug in CRM, the status REALIZE might have no user attached to it
    -- that scenario should only be possible with the RESOLVE status.
    NOT (a.id_user_action = -1 AND a.action_type = 'REALIZE')

),
proposals_contracts AS (
  SELECT
    t.id_task,
    t.id_receiver,
    t.id_origin,
    t.id_assignee,
    t.id_user_action,
    t.id_start_date,
    t.id_completed_date,
    t.id_next_action_date,
    t.id_action_date,
    COALESCE(ep.id, ec.id_proposal) AS id_proposal,
    COALESCE(ec.id, epc.id) AS id_contract,
    COALESCE(epi.id_user, eci.id_user) AS id_house_owner,
    COALESCE(ep.id_proponent, ec.id_user) AS id_tenant,
    CAST(COALESCE(eo.sk_offer, feo.sk_offer) AS BIGINT) AS id_offer,
    t.id_workgroup,
    t.type,
    t.action_user_name,
    t.action_type,
    t.action_reason,
    t.task_status,
    t.minutes_task_created_to_started,
    t.task_user_resolve_hours,
    t.ts_next_action,
    t.ts_action,
    t.dt_partition,
    t.year,
    t.month,
    t.day
  FROM
    tasks t
  JOIN
    datalake_crm.tasks ct
      ON t.id_task = ct.id
  LEFT JOIN
    datalake_ebdb_clean.contract ec
      ON  ct.origin IN ('Contrato', 'ContratoFull')
      AND ct.id_origin = ec.id
  LEFT JOIN
    datalake_ebdb_clean.house eci
      ON eci.id = ec.id_house
  LEFT JOIN
    datalake_ebdb_clean.proposal ep
      ON ct.origin = 'Proposta'
      AND CAST(CAST(ct.id_origin AS DECIMAL) AS BIGINT) = ep.id
  LEFT JOIN
    datalake_ebdb_clean.contract epc
      ON epc.id_proposal = ep.id
  LEFT JOIN
    datalake_ebdb_clean.house epi
      ON epi.id = epc.id_house
  LEFT JOIN
    dw_janus.dim_offer eo
      ON ct.origin = 'Offer'
      AND CAST(CAST(ct.id_origin AS DECIMAL) AS BIGINT) = CAST(eo.id_offer AS BIGINT)
  LEFT JOIN
    dw_janus.dim_offer feo
      ON ct.origin = 'Offer'
      AND ct.id_origin = feo.id_firestore
),
contract_proposal_house_listing AS (
  SELECT
    CAST(sk_house_listing AS BIGINT) AS sk_house_listing,
    CAST(sk_offer AS BIGINT) as sk_offer,
    CAST(sk_proposal AS BIGINT) AS sk_proposal,
    CAST(sk_owner AS BIGINT) AS sk_house_owner,
    CAST(COALESCE(if(sk_contract != '-1',sk_client, NULL),'-1') AS BIGINT) AS sk_tenant,
    CAST(COALESCE(if(sk_proposal != '-1',sk_client, NULL),'-1') AS BIGINT) AS sk_proponent,
    MAX(CAST(sk_contract AS BIGINT)) AS sk_contract
  FROM 
    testing_map_ods_from_s3.ods_fact_listing_rent_flows
  WHERE 
    sk_contract != '-1'
    OR sk_proposal != '-1'
    OR sk_offer != '-1'
  GROUP BY 1, 2, 3, 4, 5, 6
)
SELECT DISTINCT
  pc.id_task,
  pc.id_receiver,
  pc.id_start_date,
  pc.id_completed_date,
  pc.id_origin,
  pc.id_assignee,
  pc.id_user_action,
  pc.id_action_date,
  pc.id_action_date AS id_task_user_start_date,
  pc.id_next_action_date AS id_task_user_end_date,
  pc.id_workgroup,
  COALESCE(contract.sk_offer, pc.id_offer,offer.sk_offer, -1) AS id_offer,
  COALESCE(contract.sk_proposal, pc.id_proposal, offer.sk_proposal,-1) AS id_proposal,
  COALESCE(proposal.sk_contract, pc.id_contract, offer.sk_contract,-1) AS id_contract,
  COALESCE(proposal.sk_house_listing, contract.sk_house_listing, offer.sk_house_listing, -1) AS id_house_listing,
  COALESCE(contract.sk_house_owner, proposal.sk_house_owner, offer.sk_house_owner, pc.id_house_owner,-1) AS id_house_owner,
  COALESCE(contract.sk_tenant, proposal.sk_tenant, offer.sk_tenant, pc.id_tenant, -1) AS id_tenant,
  COALESCE(contract.sk_proponent, proposal.sk_proponent, offer.sk_proponent, -1) AS id_proponent,
  pc.type,
  pc.action_user_name,
  pc.action_type,
  pc.action_reason,
  pc.task_status,
  pc.action_type AS task_user_type,
  pc.minutes_task_created_to_started,
  CAST(pc.task_user_resolve_hours AS FLOAT),
  pc.ts_action AS ts_task_user_start,
  pc.ts_next_action AS ts_task_user_end,
  pc.ts_action,
  pc.dt_partition,
  pc.year,
  pc.month,
  pc.day
FROM 
  proposals_contracts pc
LEFT JOIN
  contract_proposal_house_listing proposal
    ON pc.id_proposal = proposal.sk_proposal
    AND pc.id_proposal != -1
-- the left joins below avoids a cartesian product made with an 'or'
LEFT JOIN
  contract_proposal_house_listing contract
    ON pc.id_contract = contract.sk_contract
    AND pc.id_contract != -1
LEFT JOIN
  contract_proposal_house_listing offer
    ON pc.id_offer = offer.sk_offer
    AND pc.id_offer != -1