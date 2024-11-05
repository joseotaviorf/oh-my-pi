SELECT
    id_agent,
    agent_type,
    day_of_week,
    SUM(
        CASE 
            WHEN COALESCE(last_change_reason,'') <> 'day off' THEN CAST(is_available_slot_24h AS INTEGER) 
            ELSE 0 
        END
    ) AS allocated_slots,
    SUM(
        CASE 
            WHEN COALESCE(last_change_reason,'') <> 'day off' THEN CAST(is_available_specific_slot AS INTEGER) 
            ELSE 0 
        END
    ) AS specific_allocated_slots,
    DATE_TRUNC('HOUR', ts_slot) AS ts_slot_hour,
    YEAR(ts_slot) AS year,
    MONTH(ts_slot) AS month, 
    DAY(ts_slot) AS day
FROM 
    datalake_ebdb_agents.agents_slots
WHERE 
    DATE(ts_slot) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}') + INTERVAL 21 DAYS
GROUP BY 1, 2, 3, 6, 7, 8, 9