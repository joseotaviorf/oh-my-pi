WITH
  termination_aud
  AS
  (
    SELECT
      id,
      id_contract,
      rev,
      rev_end,
      status,
      dt_termination,
      ts_updated
    FROM datalake_terminator_clean_prod.termination_aud
  ),
  terminations_finished
  AS
  (
    SELECT
      id,
      min(ts_updated) AS ts_termination_finished
    FROM termination_aud ta
    WHERE ta.status = 'DONE'
    GROUP BY 1
  ),
  terminations_modified
  AS
  (
    SELECT
      ta1.id,
    max(ta2.ts_updated)::date as dt_last_updated
    FROM termination_aud ta1
      INNER JOIN termination_aud ta2
      ON ta2.rev = ta1.rev_end
        AND ta2.id = ta1.id
    WHERE ta1.rev_end IS NOT NULL
      AND ta1.dt_termination != ta2.dt_termination
    GROUP BY 1
  ),
  inspections
  AS
  (
    SELECT
      id,
      id_contract
    FROM datalake_terminator_clean_prod.inspection i
  ),
  last_inspection
  AS
  (
    SELECT
      id_contract,
      max(id) AS id
    FROM inspections i
    GROUP BY 1
  ),
  keys
  AS
  (
    SELECT
      id_contract,
      id,
      tenant_keys_location,
      owner_keys_location
    FROM datalake_terminator_clean_prod.termination
  ),
  inspection_tasks
  AS
  (
    SELECT
      fit.sk_contract,
      ts_action,
      action_type
    FROM crm.fact_inspection_tasks fit
      JOIN crm.dim_inspection_task dit
      ON fit.sk_task = dit.sk_task
    WHERE dit.type IN ('SegundaAnaliseVistoriaSaida','AnaliseVistoriaSaida')
  ),
  inspection_task
  AS
  (
    SELECT
      sk_contract,
      MAX(CASE WHEN action_type = 'REALIZE' THEN ts_action END) AS ts_task_completed, -- Avoiding duplicated Realize status because of product bug
      MIN(CASE WHEN action_type = 'CREATE' THEN ts_action END) AS ts_task_created
    -- Avoiding duplicated tasks per contract because of product bug
    FROM inspection_tasks
    GROUP BY 1
  )
SELECT
  t.id AS sk_termination,
  t.id_contract AS sk_contract,
  t.id_exit_inspection AS sk_exit_inspection,
  JSON_EXTRACT_PATH_TEXT(t.feedback, 'reason') AS reason,
  t.feedback,
  t.requested_by,
  t.status,
  t.source,
  CASE WHEN (source = 'PWA' and dc.is_b2b= 'true' and t.ts_created < '2020-06-10')
    OR (source = 'PWA' and t.dt_termination < dc.dt_entrance)
    OR (source = 'PWA' and JSON_EXTRACT_PATH_TEXT(feedback, 'reason') = 'JOB_TRANSFER' and t.ts_created >= '2020-03-25' and dateadd(year, 1, dc.dt_entrance) > t.dt_termination)
    OR (source = 'PWA' and JSON_EXTRACT_PATH_TEXT(feedback, 'reason') = 'JOB_TRANSFER' and t.ts_created < '2020-03-25')
    THEN 'Semi-automatic'
    WHEN t.source = 'CRM' then 'Manual'
    ELSE 'Automatic'
    END AS type,
  tw.current_step AS workflow_current_step,
  JSON_EXTRACT_PATH_TEXT(k.tenant_keys_location, 'location') AS tenant_key_location,
  k.tenant_keys_location AS tenant_key_detail,
  k.owner_keys_location AS owner_key_detail,
  n.has_landlord_comment AS has_repairs,
  n.needs_repair_by_tenant AS is_repair_tenant_duty,
  n.repair_resolution,
  n.repair_cost,
  t.utility_bill_info,
  t.has_exit_inspection,
  (m.id IS NOT NULL) AS has_been_rescheduled,
  (t.ts_canceled IS NOT NULL) AS is_termination_canceled,
  (tw.id IS NOT NULL) AS is_workflow,
  (occ.sk_contract IS NOT NULL OR (tw.id IS NOT NULL AND tw.ts_created > '2021-05-19 18:00:00')) AS is_carteirizado,
  t.is_relisting,
  t.dt_termination,
  m.dt_last_updated AS dt_last_rescheduled,
  n.ts_updated::date AS dt_negotiation_updated,
  t.ts_created,
  t.ts_canceled,
  CASE WHEN d.ts_termination_finished <= '2020-07-07' THEN n.ts_updated
    WHEN d.ts_termination_finished > '2020-07-07' THEN d.ts_termination_finished
    END AS ts_termination_finished,
  t.ts_updated,
  current_timestamp as ts_load
FROM datalake_terminator_clean_prod.termination t
  LEFT JOIN terminations_finished d
  ON d.id = t.id
    AND t.status = 'DONE'
  LEFT JOIN datalake_terminator_clean_prod.negotiation n
  ON t.id=n.id_termination
  LEFT JOIN last_inspection i
  ON i.id_contract = t.id_contract
  LEFT JOIN keys k
  ON k.id = t.id
  LEFT JOIN terminations_modified m
  ON m.id = t.id
  LEFT JOIN dim_contract dc
  ON dc.sk_contract = t.id_contract
  LEFT JOIN inspection_task tc
  ON tc.sk_contract = t.id_contract 
  LEFT JOIN datalake_terminator_clean_prod.termination_workflow tw
  ON t.id = tw.id_termination
  LEFT JOIN (SELECT distinct cast(nullif(ongoing_contracts,'') AS BIGINT) AS sk_contract FROM datalake_raw.gsheets_offboarding_carteirizacao_contratos
            UNION all
            SELECT distinct cast(nullif(finished_contracts,'') AS BIGINT) AS sk_contract FROM datalake_raw.gsheets_offboarding_carteirizacao_contratos) occ 
  ON t.id_contract = occ.sk_contract 