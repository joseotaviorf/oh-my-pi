SELECT
    CAST(ash.id_agent AS INT) AS sk_agent,
    CAST(ash.id_slot_date AS INT) AS sk_slot_date,
    CAST(ash.id_slot_date_hour AS BIGINT) AS sk_slot_date_hour,
    CAST(ash.id_agent_region AS STRING) AS sk_agent_region,
    CAST(ash.id_slot_date_agent AS BIGINT) AS sk_slot_date_agent,
    CAST(ash.id_work_contract AS INT) AS id_work_contract,
    CAST(u.id_photographer_data AS INTEGER) AS id_dados_fotografo,
    CAST(ash.ts_slot_hour AS TIMESTAMP) AS ts_slot_hour,
    CAST(ash.allocated_slots AS INT) AS allocated_slots,
    CAST(ash.specific_allocated_slots AS INT) AS allocated_slots_0,
    ash.area_deprecated AS area,
    ash.is_allocation_available,
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