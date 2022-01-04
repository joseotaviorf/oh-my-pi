WITH agents_slots_hourly AS (
    SELECT
        id_agent,
        COALESCE(CAST(DATE_FORMAT(ts_slot_hour,'yyyyMMdd') AS BIGINT), -1) AS id_slot_date,
        agent_type,
        day_of_week,
        allocated_slots,
        specific_allocated_slots,
        ts_slot_hour
    FROM
        datalake_ebdb_agents.agents_slots_hourly
    WHERE
        agent_type IN ('Vistoria', 'VistoriaQuarteirizada')
        AND DATE(ts_slot_hour) BETWEEN DATE('{year}-{month}-{day}') AND (DATE('{year}-{month}-{day}') + INTERVAL 21 DAYS)
),
agents_region AS (
    SELECT
        id_agent,
        id_region,
        MAX(ts_ended) AS ts_ended,
        MAX(ts_started) AS ts_started
    FROM
        datalake_ebdb_agents.agents_region
    WHERE
        ts_revision <= TIMESTAMP('{year}-{month}-{day}')
    GROUP BY 1, 2
    HAVING
        ts_started >= COALESCE(ts_ended, ts_started)
),
first_inspection AS (
    SELECT
        id_agent,
        MIN(dt_booking) AS dt_first_inspection
    FROM 
        datalake_ebdb_clean.booking
    WHERE 
        type IN ('Vistoria', 'VistoriaQuarteirizada')
    GROUP BY 1
),
agent_contract_rank AS (
    SELECT DISTINCT
        aud.id AS id_agent,
        FIRST_VALUE(id_work_contract) OVER(PARTITION BY aud.id ORDER BY ure.ts_revision DESC) AS id_work_contract
    FROM
        datalake_ebdb_clean.agent_data_aud AS aud
        JOIN 
            datalake_ebdb_clean.user_revision_entity AS ure 
                ON aud.rev = ure.id
    WHERE
        ure.ts_revision <= 1000*TO_UNIX_TIMESTAMP(DATE('{year}-{month}-{day}'), 'yyyy-MM-dd')
)
SELECT DISTINCT
    ash.id_agent AS sk_agent,
    CAST(CAST(ash.id_slot_date AS STRING) || CAST(ash.id_agent AS STRING) AS BIGINT) AS sk_agent_region,
    CAST(CAST(ash.id_slot_date AS STRING) || CAST(ash.id_agent AS STRING) AS BIGINT) AS sk_agent_slot_date,
    CAST(COALESCE(ar.id_region, '-1') AS BIGINT) AS sk_region,
    ash.id_slot_date AS sk_slot_date,
    CAST(DATE_FORMAT(ash.ts_slot_hour,'yyyyMMddHH') AS BIGINT) AS sk_slot_date_hour, 
    CAST(COALESCE(acr.id_work_contract, -1) AS BIGINT) AS sk_work_contract,
    ash.agent_type,
    CAST(ash.allocated_slots AS SMALLINT) AS allocated_slots,
    CAST(ash.specific_allocated_slots AS SMALLINT) AS specific_allocated_slots,
    CASE EXTRACT(HOUR FROM ash.ts_slot_hour)
        WHEN  8 THEN COALESCE(mwh.has_hours_between_08_and_09_available,FALSE)
        WHEN  9 THEN COALESCE(mwh.has_hours_between_09_and_10_available,FALSE)
        WHEN 10 THEN COALESCE(mwh.has_hours_between_10_and_11_available,FALSE)
        WHEN 11 THEN COALESCE(mwh.has_hours_between_11_and_12_available,FALSE)
        WHEN 12 THEN COALESCE(mwh.has_hours_between_12_and_13_available,FALSE)
        WHEN 13 THEN COALESCE(mwh.has_hours_between_13_and_14_available,FALSE)
        WHEN 14 THEN COALESCE(mwh.has_hours_between_14_and_15_available,FALSE)
        WHEN 15 THEN COALESCE(mwh.has_hours_between_15_and_16_available,FALSE)
        WHEN 16 THEN COALESCE(mwh.has_hours_between_16_and_17_available,FALSE)
        WHEN 17 THEN COALESCE(mwh.has_hours_between_17_and_18_available,FALSE)
        WHEN 18 THEN COALESCE(mwh.has_hours_between_18_and_19_available,FALSE)
        WHEN 19 THEN COALESCE(mwh.has_hours_between_19_and_20_available,FALSE)
        ELSE FALSE
    END AS is_allocation_available,
    dt_first_inspection,
    ash.ts_slot_hour,
    EXTRACT(year FROM ts_slot_hour) AS year,
    EXTRACT(month FROM ts_slot_hour) AS month,
    EXTRACT(day FROM ts_slot_hour) AS day,
    NOW() AS ts_load 
FROM
    agents_slots_hourly AS ash
JOIN 
    agents_region AS ar 
        ON ar.id_agent = ash.id_agent
LEFT JOIN 
    first_inspection fv
        ON fv.id_agent = ash.id_agent
LEFT JOIN 
    agent_contract_rank AS acr
        ON acr.id_agent = ash.id_agent
LEFT JOIN 
    datalake_ebdb_clean.mask_weekly_hour AS mwh
        ON mwh.id_work_contract  = acr.id_work_contract 
        AND MOD(mwh.day_of_week, 7) = MOD(ash.day_of_week, 7)