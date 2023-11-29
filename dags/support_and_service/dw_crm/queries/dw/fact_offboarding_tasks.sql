WITH contracts AS (
  SELECT
    turf.id_task AS sk_task,
    turf.id_receiver AS sk_receiver,
    turf.id_start_date AS sk_start_date,
    turf.id_completed_date AS sk_completed_date,
    turf.id_origin AS sk_origin,
    turf.id_assignee AS sk_assignee,
    turf.id_user_action AS sk_user_action,
    turf.id_action_date AS sk_action_date,
    CAST(COALESCE(ec.id, ib.id_contract, -1) AS BIGINT) AS sk_contract,
    CAST(COALESCE(eo.id, -1) AS BIGINT) AS sk_rent_flow,
    turf.id_task_user_start_date AS sk_task_action_start_date,
    turf.id_task_user_end_date AS sk_task_action_end_date,
    turf.action_user_name,
    turf.action_type,
    turf.task_user_type AS task_action_type,
    turf.task_user_resolve_hours,
    turf.ts_action,
    turf.ts_task_user_start AS ts_task_action_start,
    turf.ts_task_user_end AS ts_task_action_end,
    turf.year,
    turf.month,
    turf.day
  FROM
    datalake_crm_tasks_flows.tasks_users_resolutions_flow turf
  LEFT JOIN
    datalake_ebdb_clean.contract ec
      ON turf.origin = 'Contrato'
      AND turf.id_origin = ec.id
  LEFT JOIN
    datalake_ebdb_clean.rent_flow eo
      ON turf.origin = 'FluxoLocacao'
      AND turf.id_origin = eo.id
  LEFT JOIN
    datalake_inspections.inspection_booking AS ib
      ON turf.origin = 'Vistoria'
      AND turf.id_origin = ib.id_external
  WHERE
    (
        turf.type IN (
            'DataDeRescisaoAlterada',
            'EncerrarContrato',
            'FollowUpReparosRescisao',
            'OrientarInquilinoRescisao',
            'OrientarProprietarioRescisao',
            'OrientarInquilinoDesocupacao',
            'ProtecaoReparosRescisao',
            'RescisaoPreVigencia',
            'RescisaoCancelada',
            'RevisarCancelamentoDeRescisao',
            'RevisarPagamentosRescisao',
            'VerificarDesocupacaoImovel'
        )
        OR (
            turf.type = 'Manual'
            AND turf.id_workgroup IN (
                'DEP_OFFBOARDING_2',
                'DEP_OFFBOARDING_ID',
                'DEP_OFFBOARDING_WORKFLOW_ID',
                'DEP_OFFBOARDING_WORKFLOW_STEP_ONE_ID',
                'DEP_OFFBOARDING_WORKFLOW_STEP_TWO_ID',
                'DEP_OFFBOARDING_WORKFLOW_STEP_THREE_ID'
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
  COALESCE(chl_contract.sk_contract, -1) AS sk_contract,
  COALESCE(chl_contract.sk_house_listing, chl_rent_flow.sk_house_listing, -1) AS sk_house_listing,
  COALESCE(chl_contract.sk_house_owner, chl_rent_flow.sk_house_owner, -1) AS sk_house_owner,
  COALESCE(chl_contract.sk_tenant, chl_rent_flow.sk_tenant, -1) AS sk_tenant,
  c.sk_task_action_start_date,
  c.sk_task_action_end_date,
  c.action_user_name,
  c.action_type,
  c.task_action_type,
  c.task_user_resolve_hours AS task_user_action_resolve_hours,
  c.ts_action,
  c.ts_task_action_start,
  c.ts_task_action_end,
  NOW() AS ts_load,
  c.year,
  c.month,
  c.day
FROM
  contracts c
LEFT JOIN
  contract_house_listing chl_contract
    ON c.sk_contract = chl_contract.sk_contract
    AND c.sk_contract != -1
LEFT JOIN
  contract_house_listing chl_rent_flow
    ON c.sk_rent_flow = chl_rent_flow.sk_rent_flow
    AND c.sk_rent_flow != -1