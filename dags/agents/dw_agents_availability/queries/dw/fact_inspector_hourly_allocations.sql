SELECT DISTINCT
    ash.id_agent AS sk_agent,
    ash.id_agent_region AS sk_agent_region,
    ash.id_slot_date_agent AS sk_agent_slot_date,
    CAST(ash.id_region AS BIGINT) AS sk_region,
    ash.id_slot_date AS sk_slot_date,
    ash.id_slot_date_hour AS sk_slot_date_hour, 
    ash.id_work_contract AS sk_work_contract,
    ash.agent_type,
    CAST(ash.allocated_slots AS SMALLINT) AS allocated_slots,
    CAST(ash.specific_allocated_slots AS SMALLINT) AS specific_allocated_slots,
    ash.is_allocation_available,
    DATE(ash.ts_first_inspection_booked) AS dt_first_inspection,
    ash.ts_slot_hour,
    NOW() AS ts_load,
    ash.year AS year,
    ash.month AS month,
    ash.day AS day
FROM
    datalake_agenda_allocation.agenda_hourly_allocations AS ash
WHERE
    ash.agent_type IN ('Vistoria', 'VistoriaQuarteirizada')