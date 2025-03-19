SELECT
    CAST(ash.id_agent AS INT) AS sk_agent,
    CAST(ash.id_slot_date AS INT) AS sk_slot_date,
    ash.id_slot_date_hour AS sk_slot_date_hour, 
    CAST(ash.id_agent_region AS STRING) AS sk_agent_region,
    ash.id_slot_date_agent AS sk_slot_date_agent,
    CAST(ash.id_work_contract AS INT) AS id_work_contract,
    u.id_photographer_data AS id_dados_fotografo,
    ash.ts_slot_hour,
    CAST(ash.allocated_slots AS INT) AS allocated_slots,
    CAST(ash.specific_allocated_slots AS INT) AS allocated_slots_0,
    ash.is_allocation_available,
    ash.area_deprecated AS area,
    NOW() AS ts_load,
    ash.year AS year,
    ash.month AS month,
    ash.day AS day
FROM 
    datalake_agenda_allocation.agenda_hourly_allocations AS ash
LEFT JOIN
    datalake_ebdb_clean.user AS u
        ON u.id_agent = ash.id_agent
WHERE
    ash.agent_type IN ('SessaoFotos')