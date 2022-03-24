SELECT 
    MAX(ct.sk_termination) AS id, 
    ct.sk_contract AS id_contract,
    ct.id_house,
    CASE 
        WHEN ct.sk_exit_inspection IS NOT NULL THEN ct.sk_exit_inspection 
        ELSE valid_insp.id 
    END AS id_exit_inspection,
    ct.status,
    ct.workflow_current_step,
    ct.reason,
    ct.repair_resolution,
    ct.repair_cost,
    ct.has_repairs,
    ct.is_repair_tenant_duty,
    ct.is_workflow,
    MAX(ct.dt_termination) AS dt_termination,
    MAX(ct.ts_created) AS ts_termination_request,
    MAX(ct.ts_termination_finished) AS ts_termination_finished
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