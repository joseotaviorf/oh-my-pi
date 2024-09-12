WITH offers AS (
  SELECT
    id,
    id_offer_context,
    NULL AS id_firestore
  FROM
    datalake_ebdb_proposal.pre_proposal
  UNION
  SELECT
    id,
    id_offer_context,
    id_firestore
  FROM
    datalake_offer.offer
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
    CAST(COALESCE(eo.id_offer_context, feo.id_offer_context) AS BIGINT) AS id_offer,
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
    datalake_crm_tasks_history_flows.tasks_history_users_flow t
  JOIN
    datalake_crm.tasks ct
      ON t.id_task = ct.id
  LEFT JOIN
    datalake_ebdb_clean.contract ec
      ON LOWER(ct.origin) IN ('contrato', 'contratofull')
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
    offers eo
      ON ct.origin = 'Offer'
      AND CAST(CAST(ct.id_origin AS DECIMAL) AS BIGINT) = CAST(eo.id AS BIGINT)
  LEFT JOIN
    offers feo
      ON ct.origin = 'Offer'
      AND ct.id_origin = feo.id_firestore
),
house_listing AS (
  SELECT
    hl.id_house_listing,
    hl.id_contract,
    hl.id_house,
    hl.ts_listing_version_start,
    COALESCE(hl.ts_listing_version_end, NOW()) AS ts_listing_version_end
  FROM
    datalake_ebdb_listing.house_listing AS hl
  UNION
  SELECT
    lc.id_house_listing,
    lc.id_contract,
    lc.id_house,
    lc.ts_listing_version_started AS ts_listing_version_start,
    lc.ts_listing_version_ended AS ts_listing_version_end
  FROM
    datalake_listing_contracts.listing_contracts AS lc
),
contract_proposal_house_listing AS (
  SELECT DISTINCT
    COALESCE(hl.id_house_listing, -1) AS sk_house_listing,
    COALESCE(rf.id_offer_context, -1) AS sk_offer,
    COALESCE(rf.id_proposal, -1) AS sk_proposal,
    COALESCE(rf.id_owner, -1) AS sk_house_owner,
    CASE
      WHEN rf.id_contract IS NOT NULL THEN rf.id_client
      ELSE -1
    END AS sk_tenant,
    CASE
      WHEN rf.id_proposal IS NOT NULL THEN rf.id_client
      ELSE -1
    END AS sk_proponent,
    COALESCE(rf.id_contract, -1) AS sk_contract
  FROM
    house_listing AS hl
  LEFT JOIN
    datalake_ebdb_rent_flow.rent_flow AS rf
      ON rf.id_contract = hl.id_contract
      OR (
        rf.id_house = hl.id_house
        AND rf.dt_rent_flow_created BETWEEN hl.ts_listing_version_start AND hl.ts_listing_version_end
      )
  WHERE
    rf.id_contract IS NOT NULL
    OR rf.id_offer_context IS NOT NULL
    OR rf.id_proposal IS NOT NULL
)
SELECT DISTINCT
  pc.id_task AS sk_task,
  pc.id_receiver AS sk_receiver,
  pc.id_start_date AS sk_start_date,
  pc.id_completed_date AS sk_completed_date,
  COALESCE(CAST(pc.id_origin AS BIGINT), -1) AS sk_origin,
  pc.id_assignee AS sk_assignee,
  pc.id_user_action AS sk_user_action,
  pc.id_action_date AS sk_action_date,
  pc.id_next_action_date AS sk_task_action_end_date,
  pc.id_action_date AS sk_task_action_start_date,
  COALESCE(contract.sk_offer, pc.id_offer,offer.sk_offer, -1) AS sk_offer,
  COALESCE(contract.sk_proposal, pc.id_proposal, offer.sk_proposal,-1) AS sk_proposal,
  COALESCE(proposal.sk_contract, pc.id_contract, offer.sk_contract,-1) AS sk_contract,
  COALESCE(proposal.sk_house_listing, contract.sk_house_listing, offer.sk_house_listing, -1) AS sk_house_listing,
  COALESCE(contract.sk_house_owner, proposal.sk_house_owner, offer.sk_house_owner, pc.id_house_owner,-1) AS sk_house_owner,
  COALESCE(contract.sk_tenant, proposal.sk_tenant, offer.sk_tenant, pc.id_tenant, -1) AS sk_tenant,
  COALESCE(contract.sk_proponent, proposal.sk_proponent, offer.sk_proponent, -1) AS sk_proponent,
  pc.action_type AS task_action_type,
  pc.minutes_task_created_to_started AS minutes_task_created_to_started,
  pc.task_user_resolve_hours AS task_user_action_resolve_hours,
  pc.action_user_name,
  pc.action_type,
  pc.action_reason,
  pc.task_status,
  pc.ts_action,
  pc.ts_action AS ts_task_action_start,
  pc.ts_next_action AS ts_task_action_end,
  NOW() AS ts_load,
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
WHERE
  (
      type IN (
        'FrontEnd',
        'CriarMinuta',
        'AprovarMinuta',
        'FollowUpAssinaturas',
        'EnviarContratoViaEmail',
        'AnalisarDocumentacaoProprietario',
        'AlinhamentoComPP',
        'VerificacaoComIQ'
    )
    OR (
        type = 'Manual'
        AND id_workgroup IN ('DEP_CLOSING_ID','DEP_AGREEMENT_MANUAL_TASK_ID')
    )
  )
  AND year = {year}
  AND month = {month}
  AND day = {day}
