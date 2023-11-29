WITH contracts AS (
  SELECT
    turf.id_task AS sk_task,
    turf.id_receiver AS sk_receiver,
    turf.id_start_date AS sk_start_date,
    turf.id_completed_date AS sk_completed_date,
    turf.id_origin AS sk_origin,
    turf.id_activity AS sk_activity,
    turf.id_assignee AS sk_assignee,
    turf.id_user_action AS sk_user_action,
    turf.id_action_date AS sk_action_date,
    COALESCE(ec.id, eo.id_contrato, ec_refund.id, -1) AS sk_contract,
    turf.id_task_user_start_date AS sk_task_action_start_date,
    turf.id_task_user_end_date AS sk_task_action_end_date,
    turf.action_user_name,
    turf.action_type,
    turf.type_activity,
    turf.task_user_type AS task_action_type,
    turf.task_user_resolve_hours AS task_user_action_resolve_hours,
    turf.ts_action,
    turf.ts_task_user_start AS ts_task_action_start,
    turf.ts_task_user_end AS ts_task_action_end,
    turf.year,
    turf.month,
    turf.day
  FROM
    datalake_crm_tasks_flows.tasks_users_resolutions_flow AS turf
  LEFT JOIN
    datalake_ebdb_clean.contract AS ec
      ON turf.origin = 'Contrato'
      AND turf.id_origin = ec.id
  LEFT JOIN
    datalake_ebdb_clean.onboarding AS eo
      ON turf.origin = 'Onboarding'
      AND turf.id_origin = eo.id
  LEFT JOIN
    datalake_ebdb_clean.contract AS ec_refund
      ON turf.origin IN ('Refund', 'TenantRefund', 'LandlordRefundCondominium')
      AND turf.id_contract = ec_refund.id
  WHERE
      turf.type IN (
        'BuscarPrimeiroBoleto',
        'PedidoDeReembolso',
        'ConfirmarBoletoCondominio',
        'PedidoDeReembolsoInquilino',
        'PedidoDeReembolsoInquilinoReparoPagamento',
        'PedidoDeReembolsoInquilinoCondominio',
        'PedidoDeReembolsoInquilinoReparo',
        'PedidoDeReembolsoProprietarioCondominio',
        'AceiteDaAntecipacaoAluguel'
      )
      OR (
        turf.type = 'Manual'
        AND turf.id_workgroup IN (
          'DEP_FINANCEIRO_ID',
          'DEP_PAYMENTS_SELFCONDO',
          'DEP_OFFBOARDING_FINANCEIRO',
          'DEP_ACORDOS_DESCONTOS_ID',
          'DEP_ONBOARDING_FINANCEIRO',
          'DEP_ID_PAYMENTS_PROJECTS',
          'DEP_ID_FINANCEIRO_PAYMENTS'
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
  c.sk_origin,
  c.sk_activity,
  c.sk_assignee,
  c.sk_user_action,
  c.sk_action_date,
  c.sk_contract,
  COALESCE(chl.sk_house_listing, -1) AS sk_house_listing,
  COALESCE(chl.sk_house_owner, -1) AS sk_house_owner,
  COALESCE(chl.sk_tenant, -1) AS sk_tenant,
  c.sk_task_action_start_date,
  c.sk_task_action_end_date,
  c.action_user_name,
  c.action_type,
  c.type_activity,
  c.task_action_type,
  c.task_user_action_resolve_hours,
  c.ts_action,
  c.ts_task_action_start,
  c.ts_task_action_end,
  NOW() AS ts_load,
  c.year,
  c.month,
  c.day
FROM
  contracts AS c
LEFT JOIN
  contract_house_listing AS chl
    ON c.sk_contract = chl.sk_contract
    AND c.sk_contract != -1
