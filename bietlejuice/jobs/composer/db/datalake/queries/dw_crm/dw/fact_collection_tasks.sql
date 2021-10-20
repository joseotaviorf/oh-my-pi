WITH contracts AS (
  SELECT
    turf.*,
    CAST(COALESCE(dc.sk_contract, '-1') AS BIGINT) AS sk_contract,
    COALESCE(eo.id, -1) AS sk_rent_flow
  FROM 
    datalake_crm_tasks_flows.tasks_users_resolutions_flow turf
  LEFT JOIN 
    dw_janus.dim_contract dc
      ON turf.origin = 'Contrato'
      AND CAST(CAST(turf.id_origin AS decimal) AS BIGINT) = CAST(dc.sk_contract AS BIGINT)
  LEFT JOIN  
    datalake_ebdb_clean.rent_flow eo
      ON turf.origin = 'FluxoLocacao'
      AND CAST(CAST(turf.id_origin AS decimal) AS BIGINT) = eo.id
  WHERE
    turf.year = {year}
    AND turf.month = {month}
    AND turf.day = {day}
    AND turf.id_workgroup = 'DEP_COLLECTIONS_ID'
),
contract_house_listing AS (
  SELECT
    CAST(sk_contract AS BIGINT) AS sk_contract,
    CAST(sk_house_listing AS BIGINT) AS sk_house_listing,
    CAST(sk_owner AS BIGINT) AS sk_house_owner,
    CAST(sk_rent_flow AS BIGINT) AS sk_rent_flow,
    CAST(sk_client AS BIGINT) AS sk_tenant
  FROM 
    testing_map_ods_from_s3.ods_fact_listing_rent_flows
  WHERE 
    sk_contract != '-1'
  GROUP BY 1, 2, 3, 4, 5
)
SELECT DISTINCT
  c.id_task AS sk_task,
  c.id_action_date AS sk_action_date,
  c.id_assignee AS sk_assignee,
  c.id_completed_date AS sk_completed_date,
  COALESCE(chl_contract.sk_contract, chl_rent_flow.sk_contract, -1) AS sk_contract,
  COALESCE(chl_contract.sk_house_listing, chl_rent_flow.sk_house_listing, -1) AS sk_house_listing,
  COALESCE(chl_contract.sk_house_owner, chl_rent_flow.sk_house_owner, -1) AS sk_house_owner,
  COALESCE(CAST(c.id_origin AS BIGINT), -1) AS sk_origin,
  c.id_receiver AS sk_receiver,
  c.id_start_date AS sk_start_date,
  c.id_task_user_end_date AS sk_task_action_end_date,
  c.id_task_user_start_date AS sk_task_action_start_date,
  COALESCE(chl_contract.sk_tenant, chl_rent_flow.sk_tenant, -1) AS sk_tenant,
  c.id_user_action AS sk_user_action,
  c.action_type,
  c.action_user_name,
  c.task_user_type AS task_action_type,
  c.task_user_resolve_hours AS task_user_action_resolve_hours,
  c.ts_action,
  c.ts_task_user_end AS ts_task_action_end,
  c.ts_task_user_start AS ts_task_action_start,
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