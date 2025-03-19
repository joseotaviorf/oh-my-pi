WITH specific_schedule AS (
    SELECT
        id_agent, 
        slot_number,
        is_available_slot,
        is_off_work,
        FROM_UNIXTIME(UNIX_TIMESTAMP(dt_agent_specific_hour, 'yyyy-MM-dd') + 15*(slot_number)*60 + 8*3600,'yyyy-MM-dd HH:mm:ss') AS ts_slot,
        max(ts_updated) OVER (PARTITION BY id_agent, dt_agent_specific_hour) AS ts_updated
    FROM
        datalake_ebdb_clean.agent_specific_hour 
    LATERAL VIEW POSEXPLODE(
        ARRAY_REPEAT(is_available_between_08_and_09, 4) ||
        ARRAY_REPEAT(is_available_between_09_and_10, 4) ||
        ARRAY_REPEAT(is_available_between_10_and_11, 4) ||
        ARRAY_REPEAT(is_available_between_11_and_12, 4) ||
        ARRAY_REPEAT(is_available_between_12_and_13, 4) ||
        ARRAY_REPEAT(is_available_between_13_and_14, 4) ||
        ARRAY_REPEAT(is_available_between_14_and_15, 4) ||
        ARRAY_REPEAT(is_available_between_15_and_16, 4) ||
        ARRAY_REPEAT(is_available_between_16_and_17, 4) ||
        ARRAY_REPEAT(is_available_between_17_and_18, 4) ||
        ARRAY_REPEAT(is_available_between_18_and_19, 4) ||
        ARRAY_REPEAT(is_available_between_19_and_20, 4)  
    ) AS slot_number, is_available_slot
)
SELECT 
    id_agent,
    slot_number,
    CAST(is_available_slot AS BOOLEAN) AS is_available_slot,
    CAST(is_off_work AS BOOLEAN) AS is_off_work,
    CAST(ts_slot AS TIMESTAMP) AS ts_slot,
    CAST(ts_updated AS TIMESTAMP) AS ts_updated
FROM
    specific_schedule