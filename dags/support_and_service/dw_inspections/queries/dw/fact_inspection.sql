SELECT
    i.id_inspection AS sk_inspection,
    i.id_external AS sk_main_inspection,
    i.id_previous_inspection AS sk_previous_inspection,
    i.id_inspector AS sk_inspector,
    i.id_assessment AS sk_assessment,
    i.id_booking AS sk_booking,
    i.id_contract AS sk_contract,
    i.id_country AS sk_country,
    i.id_city AS sk_city,
    i.country_code,
    i.booking_type,
    im.ldt_hours_execution,
    im.sla_execution_target,
    im.is_sla_execution,
    i.is_d0_canceled,
    i.is_d1_canceled,
    i.dt_contract_entrance,
    i.dt_contract_termination,
    i.dt_execution_limit,
    i.ts_inspected,
    i.ts_first_synced,
    i.ts_booking_inspected_utc AS ts_booking_inspected,
    i.ts_booking_inspected_local_tz AS ts_booking_inspected_local,
    i.ts_booking_cancelled_utc AS ts_booking_cancelled,
    i.ts_booking_cancelled_local_tz AS ts_booking_cancelled_local,
    i.ts_termination_canceled,
    i.ts_created,
    NOW() AS ts_load
FROM
    datalake_inspections.inspection_booking i
LEFT JOIN
    datalake_inspections_metrics.inspection_achievements im
        ON im.id_inspection = i.id_inspection