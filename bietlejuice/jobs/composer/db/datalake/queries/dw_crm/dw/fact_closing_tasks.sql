WITH proposals_contracts AS (
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
    datalake_crm_tasks_history_flows.tasks_history_users_flow t
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
    dw_public.dim_offer eo
      ON ct.origin = 'Offer'
      AND CAST(CAST(ct.id_origin AS DECIMAL) AS BIGINT) = CAST(eo.id_offer AS BIGINT)
  LEFT JOIN
    dw_public.dim_offer feo
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
    dw_public.fact_listing_rent_flows
  WHERE 
    sk_contract != '-1'
    OR sk_proposal != '-1'
    OR sk_offer != '-1'
  GROUP BY 1, 2, 3, 4, 5, 6
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
        AND id_workgroup IN ('DEP_CLOSING_ID')
    )
  )
  AND year = {year}
  AND month = {month}
  AND day = {day}