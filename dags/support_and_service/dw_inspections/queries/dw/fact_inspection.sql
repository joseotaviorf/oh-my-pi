SELECT
    i.id_inspection AS sk_inspection,
    i.id_external AS sk_main_inspection,
    i.id_client_side AS sk_client_side,
    i.id_previous_inspection AS sk_previous_inspection,
    i.id_inspector AS sk_inspector,
    i.id_assessment AS sk_assessment,
    i.id_booking AS sk_booking,
    i.id_contract AS sk_contract,
    i.id_house AS sk_house,
    i.id_country AS sk_country,
    i.id_city AS sk_city,
    i.country_code,
    i.booking_type,
    im.ldt_hours_execution,
    im.sla_execution_target,
    im.is_sla_execution,
    i.is_d0_canceled,
    i.is_d1_canceled,
    i.is_not_canceled_by_inspector,
    i.is_first_schedule,
    i.is_executed_in_first_schedule,
    i.dt_contract_entrance,
    i.dt_contract_termination,
    i.dt_execution_limit,
    i.ts_inspected,
    i.ts_synced,
    i.ts_booking_created_utc AS ts_booking_created,
    i.ts_booking_created_local_tz AS ts_booking_created_local,
    i.ts_booking_inspected_utc AS ts_booking_inspected,
    i.ts_booking_inspected_local_tz AS ts_booking_inspected_local,
    i.ts_booking_cancelled_utc AS ts_booking_cancelled,
    i.ts_booking_cancelled_local_tz AS ts_booking_cancelled_local,
    i.ts_termination_canceled,
    i.ts_created,
    i.ts_updated,
    NOW() AS ts_load,
    YEAR(i.ts_updated) AS year,
    MONTH(i.ts_updated) AS month,
    DAY(i.ts_updated) AS day
FROM
    datalake_inspections.inspection_booking i
LEFT JOIN
    datalake_inspections_metrics.inspection_achievements im
        ON im.id_assessment = i.id_assessment
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY i.id_inspection ORDER BY i.ts_updated DESC) = 1
