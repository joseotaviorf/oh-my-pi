SELECT
    MAX(ct.id_termination) AS id,
    ct.id_contract,
    ct.id_house,
    ct.id_exit_inspection,
    ct.category,
    ct.status,
    ct.workflow_current_step,
    ct.reason,
    ct.repair_resolution,
    ct.repair_cost,
    ct.contract_status,
    ct.b2b_type,
    ct.has_repairs,
    ct.is_repair_tenant_duty,
    ct.is_workflow,
    ct.is_b2b,
    ct.is_contract_b2b,
    ct.is_exit_inspection_opted_out,
    MAX(ct.dt_contract_started) AS dt_contract_started,
    MAX(ct.dt_contract_entrance) AS dt_contract_entrance,
    MAX(ct.dt_last_inspection_synched) AS dt_last_inspection_synched,
    MAX(ct.dt_termination) AS dt_termination,
    MAX(insp.ts_created) AS ts_created_inspection,
    MAX(ct.ts_created) AS ts_termination_request,
    MAX(ct.ts_termination_finished) AS ts_termination_finished,
    MAX(ct.ts_analyst_annulment_input) AS ts_analyst_annulment_input
FROM
    datalake_offboarding.contract_termination ct
LEFT JOIN
    datalake_inspections.inspection_booking insp
        ON insp.id_contract = ct.id_contract
        AND insp.inspection_type IN ('offboarding','verification')
        AND insp.status <> 'cancelled'
WHERE
    (
        (
            ct.dt_termination >= CURRENT_DATE + INTERVAL '-30' WEEK
            OR ct.ts_termination_finished >= CURRENT_DATE + INTERVAL '-20' WEEK
        )
        AND (
            ct.ts_termination_finished <= CURRENT_DATE + INTERVAL '1' WEEK
            OR ct.dt_termination <= CURRENT_DATE + INTERVAL '10' WEEK
        )
        AND ct.status NOT IN ('CANCELED')
    )
    OR (
        ct.dt_termination <= CURRENT_DATE + INTERVAL '10' WEEK
        AND ct.status NOT IN ('CANCELED', 'DONE')
    )
GROUP BY 2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18