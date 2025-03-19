SELECT DISTINCT
    CAST(ash.id_agent AS BIGINT) AS sk_agent,
    CAST(ash.id_agent_region AS BIGINT) AS sk_agent_region,
    CAST(ash.id_slot_date_agent AS BIGINT) AS sk_agent_slot_date,
    CAST(ash.id_region AS BIGINT) AS sk_region,
    CAST(ash.id_slot_date AS BIGINT) AS sk_slot_date,
    CAST(ash.id_slot_date_hour AS BIGINT) AS sk_slot_date_hour, 
    CAST(ash.id_work_contract AS BIGINT) AS sk_work_contract,
    ash.agent_type,
    CAST(ash.allocated_slots AS SMALLINT) AS allocated_slots,
    CAST(ash.specific_allocated_slots AS SMALLINT) AS specific_allocated_slots,
    ash.is_allocation_available,
    DATE(ash.ts_first_inspection_booked) AS dt_first_inspection,
    CAST(ash.ts_slot_hour AS TIMESTAMP) AS ts_slot_hour,
    NOW() AS ts_load,
    ash.year AS year,
    ash.month AS month,
    ash.day AS day
FROM
    datalake_agenda_allocation.agenda_hourly_allocations AS ash
WHERE
    ash.agent_type IN ('Vistoria', 'VistoriaQuarteirizada')
    AND DATE(ts_slot_hour) BETWEEN DATE('{year}-{month}-{day}') AND (DATE('{year}-{month}-{day}') + INTERVAL 21 DAYS)