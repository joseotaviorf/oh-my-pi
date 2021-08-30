WITH agent_weekly_hour AS (
    SELECT DISTINCT
        id_agent,
        day_of_week,
        has_hours_between_08_and_09_available,
        has_hours_between_09_and_10_available,
        has_hours_between_10_and_11_available,
        has_hours_between_11_and_12_available,
        has_hours_between_12_and_13_available,
        has_hours_between_13_and_14_available,
        has_hours_between_14_and_15_available,
        has_hours_between_15_and_16_available,
        has_hours_between_16_and_17_available,
        has_hours_between_17_and_18_available,
        has_hours_between_18_and_19_available,
        has_hours_between_19_and_20_available,
        hsa.ts_updated
    FROM
        datalake_ebdb_clean.agent_weekly_hours_aud hsa
),
weekly_schedule_prev AS (
    SELECT 
        id_agent,
        dat.types AS agent_type,
        day_of_week,
        slot_number,
        is_available_slot,
        hsa.ts_updated
    FROM
        agent_weekly_hour hsa
    JOIN datalake_ebdb_clean.agent_data_types dat
        ON hsa.id_agent = dat.id_agent_data
    LATERAL VIEW POSEXPLODE(   
                    ARRAY_REPEAT(has_hours_between_08_and_09_available, 4) ||
                    ARRAY_REPEAT(has_hours_between_09_and_10_available, 4) ||
                    ARRAY_REPEAT(has_hours_between_10_and_11_available, 4) ||
                    ARRAY_REPEAT(has_hours_between_11_and_12_available, 4) ||
                    ARRAY_REPEAT(has_hours_between_12_and_13_available, 4) ||
                    ARRAY_REPEAT(has_hours_between_13_and_14_available, 4) ||
                    ARRAY_REPEAT(has_hours_between_14_and_15_available, 4) ||
                    ARRAY_REPEAT(has_hours_between_15_and_16_available, 4) ||
                    ARRAY_REPEAT(has_hours_between_16_and_17_available, 4) ||
                    ARRAY_REPEAT(has_hours_between_17_and_18_available, 4) ||
                    ARRAY_REPEAT(has_hours_between_18_and_19_available, 4) ||
                    ARRAY_REPEAT(has_hours_between_19_and_20_available, 4)          
                        ) AS slot_number, is_available_slot
),
weekly_schedule AS (
    SELECT
        id_agent,
        agent_type,
        day_of_week,
        slot_number,
        is_available_slot,
        lag(is_available_slot) OVER (PARTITION BY id_agent, day_of_week, slot_number ORDER BY ts_updated) AS is_available_slot_previous,
        lead(ts_updated) OVER (PARTITION BY id_agent, day_of_week, slot_number ORDER BY ts_updated) AS ts_next_updated,
        ts_updated
    FROM
        weekly_schedule_prev
),
schedule_versions AS (
    SELECT
        id_agent,
        agent_type,
        cast(day_of_week AS BIGINT) AS day_of_week,
        slot_number,
        is_available_slot,
        lead(ts_updated) OVER ( PARTITION BY id_agent, day_of_week, slot_number ORDER BY ts_updated) AS ts_next_updated,
        ts_updated
    FROM
        weekly_schedule
    WHERE
        COALESCE((is_available_slot_previous <> is_available_slot), true) = true
)
SELECT 
    id_agent,
    agent_type,
    su.day_of_week,
    su.slot_number,
    CAST(su.is_available_slot AS BOOLEAN) AS is_available_slot,
    CAST(dd.ts_slot AS TIMESTAMP) AS ts_slot,
    CAST(su.ts_updated AS TIMESTAMP) AS ts_updated
FROM
    schedule_versions su
LEFT JOIN datalake_ebdb_agents.slots_base_time dd
    ON dd.ts_slot > DATE_TRUNC('minute', su.ts_updated)
    AND dd.ts_slot <= DATE_TRUNC('minute',COALESCE(su.ts_next_updated, CURRENT_DATE + INTERVAL '1' month))
    AND dd.slot_number = su.slot_number
    AND dd.day_of_week = su.day_of_week
WHERE
    dd.ts_slot IS NOT NULL