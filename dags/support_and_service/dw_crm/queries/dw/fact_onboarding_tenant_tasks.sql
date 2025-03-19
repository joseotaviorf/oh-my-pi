WITH offers AS (
  SELECT
     o.id_firestore,
     MAX(o.id) AS id
  FROM
    datalake_offer.offer o
  GROUP BY 1
),
contracts AS (
  SELECT
    turf.id_task AS sk_task,
    turf.id_receiver AS sk_receiver,
    turf.id_start_date AS sk_start_date,
    turf.id_completed_date AS sk_completed_date,
    turf.id_origin AS sk_origin,
    turf.id_assignee AS sk_assignee,
    turf.id_user_action AS sk_user_action,
    turf.id_action_date AS sk_action_date,
    CAST(COALESCE(dc.id, CAST(eo.id_contrato AS STRING), CAST(ib.id_contract AS STRING), CAST(co.id AS STRING), '-1') as BIGINT) AS sk_contract,
    turf.id_task_user_start_date AS sk_task_user_start_date,
    turf.id_task_user_end_date AS sk_task_user_end_date,
    turf.action_user_name,
    turf.ts_action,
    turf.action_type,
    turf.ts_task_user_start,
    turf.ts_task_user_end,
    turf.task_user_type,
    turf.task_user_resolve_hours,
    turf.year,
    turf.month,
    turf.day
  FROM
    datalake_crm_tasks_flows.tasks_users_resolutions_flow turf
  LEFT JOIN
    datalake_ebdb_clean.contract dc
      ON turf.origin = 'Contrato'
      AND turf.id_origin = dc.id
  LEFT JOIN
    datalake_ebdb_clean.onboarding eo
      ON turf.origin = 'Onboarding'
      AND turf.id_origin  = eo.id
  LEFT JOIN
    datalake_inspections.inspection_booking AS ib
      ON turf.origin = 'Vistoria'
      AND turf.id_origin = ib.id_external
  LEFT JOIN
    offers o
      ON turf.origin = 'Offer'
      AND o.id_firestore = turf.id_origin
  LEFT JOIN
    datalake_ebdb_clean.proposal p
      ON o.id = p.id_offer
  LEFT JOIN
    datalake_ebdb_clean.contract co
      ON p.id = co.id
  WHERE
    (
      turf.type IN (
        'AgendarBuscaEEntregaDeChaves',
        'AtualizaInfoChavesProp',
        'AtualizaInfoChavesRecebidas',
        'BuscarChaveProprietario',
        'ConfirmarComprovantesContas',
        'ConfirmarDados',
        'ConfirmarLocalChaves',
        'ContatarInquilinoInfoEntregaChaves',
        'DevolverChavesParaProprietarios',
        'EntregaChavesParaInquilino',
        'InquilinoNaoRecebeuTodasChaves',
        'PagarContasConsumo',
        'SendLongTermEmailOwner',
        'SendLongTermEmailTenant',
        'SendShortTerm',
        'TransferenciaContasConsumoAgua',
        'TransferenciaContasConsumoGas',
        'TransferenciaContasConsumoLuz',
        'VerificarContrato'
      )
    OR (
      turf.type = 'Manual'
      AND turf.id_workgroup IN (
        'DEP_ONBOARDING_INQUILINO',
        'DEP_KEY_TRAVEL_AFTER_EXIT'
      )
    )
  )
  AND turf.year = {year}
  AND turf.month = {month}
  AND turf.day = {day}
),
house_listing AS (
  SELECT
    hl.id_house_listing,
    hl.id_contract
  FROM
    datalake_ebdb_listing.house_listing AS hl
  UNION ALL
  SELECT
    lc.id_house_listing,
    lc.id_contract
  FROM
    datalake_listing_contracts.listing_contracts AS lc
),
contract_house_listing AS (
  SELECT DISTINCT
    COALESCE(hl.id_house_listing, -1) AS sk_house_listing,
    COALESCE(rf.id_owner, -1) AS sk_house_owner,
    COALESCE(hl.id_contract, -1) AS sk_contract,
    COALESCE(rf.id_client, -1) AS sk_tenant,
    COALESCE(rf.id_rent_flow, -1) AS sk_rent_flow
  FROM
    house_listing AS hl
  LEFT JOIN
    datalake_ebdb_rent_flow.rent_flow AS rf
      ON rf.id_contract = hl.id_contract
)
SELECT DISTINCT
  c.sk_task,
  c.sk_receiver,
  c.sk_start_date,
  c.sk_completed_date,
  COALESCE(CAST(c.sk_origin AS BIGINT), -1) AS sk_origin,
  c.sk_assignee,
  c.sk_user_action,
  c.sk_action_date,
  c.sk_contract,
  COALESCE(chl.sk_house_listing, -1) AS sk_house_listing,
  COALESCE(chl.sk_house_owner, -1) AS sk_house_owner,
  COALESCE(chl.sk_tenant, -1) AS sk_tenant,
  c.sk_task_user_start_date AS sk_task_action_start_date,
  c.sk_task_user_end_date AS sk_task_action_end_date,
  c.action_user_name,
  c.action_type,
  c.task_user_type AS task_action_type,
  c.task_user_resolve_hours AS task_user_action_resolve_hours,
  c.ts_task_user_start AS ts_task_action_start,
  c.ts_task_user_end AS ts_task_action_end,
  c.ts_action,
  NOW() AS ts_load,
  c.year,
  c.month,
  c.day
FROM
  contracts c
LEFT JOIN
  contract_house_listing chl
    ON c.sk_contract = chl.sk_contract
    AND c.sk_contract != -1