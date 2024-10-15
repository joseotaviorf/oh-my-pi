SELECT
    COALESCE(i.id_inspection, -1) AS sk_inspection,
    COALESCE(i.id_external, -1) AS sk_main_inspection,
    COALESCE(i.id_client_side, -1) AS sk_client_side,
    COALESCE(i.id_previous_inspection, -1) AS sk_previous_inspection,
    COALESCE(i.id_inspector, -1) AS sk_inspector,
    COALESCE(i.id_assessment, -1) AS sk_assessment,
    COALESCE(i.id_appointment, -1) AS sk_booking,
    COALESCE(i.id_contract, -1) AS sk_contract,
    COALESCE(i.id_house, -1) AS sk_house,
    COALESCE(i.id_country, -1) AS sk_country,
    COALESCE(i.id_city, -1) AS sk_city,
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
