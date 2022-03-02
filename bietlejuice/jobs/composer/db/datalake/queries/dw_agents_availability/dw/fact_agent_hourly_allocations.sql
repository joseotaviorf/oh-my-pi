WITH agents_slots_hourly AS (
    SELECT
        id_agent,
        COALESCE(CAST(DATE_FORMAT(ts_slot_hour,'yyyyMMdd') AS INT), -1) AS id_slot_date,
        agent_type,
        day_of_week,
        allocated_slots,
        specific_allocated_slots,
        ts_slot_hour
    FROM
        datalake_ebdb_agents.agents_slots_hourly
    WHERE
        agent_type IN ('Visita')
        AND DATE(ts_slot_hour) BETWEEN DATE('{year}-{month}-{day}') AND (DATE('{year}-{month}-{day}') + INTERVAL 21 DAYS)
),
first_visits AS (
    SELECT
        id_agent,
        MIN(dt_scheduling) AS ts_first_visit
    FROM 
        dw_public.dim_booking db
    WHERE 
        db.type = 'Visita'
    GROUP BY id_agent
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
SELECT
	CAST(ash.id_agent AS INT) AS sk_agent,
	ash.id_slot_date AS sk_slot_date,
	CAST(DATE_FORMAT(ash.ts_slot_hour,'yyyyMMddHH') AS BIGINT) AS sk_slot_date_hour, 
	CAST(COALESCE(a.sk_agent_region, -1) AS STRING) AS sk_agent_region,
	CAST(CAST(ash.id_slot_date AS STRING) || CAST(ash.id_agent AS STRING) AS BIGINT) AS sk_slot_date_agent,
	CAST(COALESCE(acr.id_work_contract, -1) AS INT) AS id_work_contract,
	ash.ts_slot_hour,
    CAST(ash.allocated_slots AS INT) AS allocated_slots,
    CAST(ash.specific_allocated_slots AS INT) AS allocated_slots_0,
	CASE HOUR(ash.ts_slot_hour)
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
	COALESCE(a.area, '-1') AS area,
	ts_first_visit,
    EXTRACT(year FROM ts_slot_hour) AS year,
    EXTRACT(month FROM ts_slot_hour) AS month,
    EXTRACT(day FROM ts_slot_hour) AS day,
	NOW() AS ts_load
FROM 
    agents_slots_hourly ash
JOIN dw_public.dim_date d
	ON d.sk_date = ash.id_slot_date
LEFT JOIN dw_public.dim_agent_region a
	ON a.sk_regions_date = COALESCE(CAST(DATE_FORMAT('{year}-{month}-{day}','yyyyMMdd') AS BIGINT), -1)
		AND a.sk_agent = ash.id_agent
LEFT JOIN first_visits fv
	ON fv.id_agent = ash.id_agent
LEFT JOIN agent_contract_rank acr
    ON acr.id_agent = ash.id_agent 
LEFT JOIN 
    datalake_ebdb_clean.mask_weekly_hour AS mwh
        ON mwh.id_work_contract  = acr.id_work_contract 
            AND mod(mwh.day_of_week, 7) = mod(d.week_day, 7)