SELECT
    i.id_inspection AS sk_inspection,
    i.id_external AS sk_main_inspection,
    i.id_assessment AS sk_assessment,
    i.id_booking AS sk_booking,
    i.id_contract AS sk_contract,
    i.id_city AS sk_city,
    im.ldt_hours_execution,
    im.sla_execution_target,
    im.is_sla_execution,
    i.dt_contract_entrance,
    i.dt_contract_termination,
    i.dt_execution_limit,
    i.dt_booking_inspected,
    i.ts_booking_cancelled,
    i.ts_termination_canceled,
    im.ts_created,
    NOW() AS ts_load
FROM
    datalake_inspections.inspection i
LEFT JOIN
    datalake_inspections.inspection_metrics im
        ON im.id_inspection = i.id_inspection