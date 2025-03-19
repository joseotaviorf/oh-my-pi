SELECT
    CAST(ash.id_agent AS INT) AS sk_agent,
    ash.id_slot_date AS sk_slot_date,
    ash.id_slot_date_hour AS sk_slot_date_hour, 
    CAST(ash.id_agent_region AS STRING) AS sk_agent_region,
    ash.id_slot_date_agent AS sk_slot_date_agent,
    CAST(ash.id_work_contract AS INT) AS id_work_contract,
    ash.ts_slot_hour,
    CAST(ash.allocated_slots AS INT) AS allocated_slots,
    CAST(ash.specific_allocated_slots AS INT) AS allocated_slots_0,
    ash.agent_business_context,
    ash.is_allocation_available,
    ash.area,
    ash.ts_first_visit_booked AS ts_first_visit,
    NOW() AS ts_load,
    ash.year AS year,
    ash.month AS month,
    ash.day AS day
FROM 
    datalake_agenda_allocation.agenda_hourly_allocations AS ash
WHERE
    ash.agent_type = "Visita"
    AND DATE(ts_slot_hour) BETWEEN DATE('{year}-{month}-{day}') AND (DATE('{year}-{month}-{day}') + INTERVAL 21 DAYS)