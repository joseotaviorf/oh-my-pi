SELECT 
    MAX(ct.sk_termination) AS id, 
    ct.sk_contract AS id_contract,
    ct.id_house,
    ct.status,
    ct.workflow_current_step,
    ct.reason,
    ct.repair_resolution,
    ct.repair_cost,
    ct.has_repairs,
    ct.is_repair_tenant_duty,
    ct.is_workflow,
    ct.is_b2b,
    MAX(ct.dt_contract_started) AS dt_contract_started,
    MAX(ct.dt_contract_entrance) AS dt_contract_entrance,
    MAX(ct.dt_last_inspection_synched) AS dt_last_inspection_synched,
    MAX(ct.dt_termination) AS dt_termination,
    MAX(valid_insp.ts_created) AS ts_created_inspection,
    MAX(ct.ts_created) AS ts_termination_request,
    MAX(ct.ts_termination_finished) AS ts_termination_finished,
    MAX(ct.ts_analyst_annulment_input) AS ts_analyst_annulment_input
FROM 
    datalake_offboarding.contract_termination ct
LEFT JOIN
    datalake_ebdb_listing_jobs.inspection valid_insp
        ON valid_insp.id_contract = ct.sk_contract
        AND valid_insp.type IN ('Saida','Constatacao')
        AND valid_insp.status <> 'Cancelada'
WHERE 
    (
        (ct.dt_termination >= DATE_ADD(current_date(),7*-30) OR ct.ts_termination_finished >= DATE_ADD(current_date(),7*-20))
        AND (ct.ts_termination_finished <= DATE_ADD(current_date(),7*1) OR ct.dt_termination <= DATE_ADD(current_date(),7*10))
        AND ct.status NOT IN ('CANCELED')
    )
    OR (ct.dt_termination <= DATE_ADD(current_date(),7*10) AND ct.status NOT IN ('CANCELED', 'DONE'))
GROUP BY 
    2,3,4,5,6,7,8,9,10,11,12