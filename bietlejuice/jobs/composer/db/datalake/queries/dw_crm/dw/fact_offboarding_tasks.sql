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
    CAST(COALESCE(ec.id, ev.id_contract, -1) AS BIGINT) AS sk_contract,
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
    datalake_ebdb_clean.inspection ev
      ON turf.origin = 'Vistoria'
      AND turf.id_origin = ev.id
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
contract_house_listing AS (
  SELECT
    CAST(sk_house_listing AS BIGINT) as sk_house_listing,
    CAST(sk_owner AS BIGINT) AS sk_house_owner,
    CAST(sk_contract AS BIGINT) AS sk_contract,
    CAST(sk_client AS BIGINT) AS sk_tenant,
    CAST(sk_rent_flow AS BIGINT) AS sk_rent_flow
  FROM
    testing_map_ods_from_s3.ods_fact_listing_rent_flows
  WHERE
    sk_contract != '-1'
  GROUP BY 1, 2, 3, 4, 5
)
SELECT DISTINCT
  c.sk_task,
  c.sk_receiver,
  c.sk_start_date,
  c.sk_completed_date,
  c.sk_origin,
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
  CAST(c.task_user_resolve_hours AS FLOAT) AS task_user_action_resolve_hours,
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