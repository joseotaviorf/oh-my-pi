WITH schedule AS (
SELECT
	t.agent_id AS sk_agent_id,
	COALESCE(to_char(t.slot_dt::DATE,'YYYYMMDD')::INTEGER, -1) AS sk_date,
    date_trunc('h', t.slot_dt) AS ts_slot_hour,
	sum(case when coalesce(t.last_change_reason,'') <> 'day off' then cast(t.available_slot_24h AS INTEGER) else 0 end) AS available_slots,
	sum(case when coalesce(t.last_change_reason,'') <> 'day off' then cast(t.specific_slot AS INTEGER) else 0 end) AS available_slots_0
FROM agent.agents_slots t
WHERE DATE(t.slot_dt) BETWEEN DATE('{0}') AND (DATE('{0}') + INTERVAL '21 days') and t.agent_type = 'SessaoFotos'
GROUP BY 1, 2, 3
),
user_workcontract_id AS (
SELECT
       agent_id,
       workcontract_id
FROM agent.agent_contract
WHERE workcontract_id IN (18, 21)
    AND workcontract_id IS NOT NULL
GROUP BY agent_id, workcontract_id
)
SELECT
	s.sk_agent_id,
	u.dados_fotografo_id,
	s.sk_date,
	COALESCE(a.sk_agent_region, -1) AS sk_agent_region,
	s.available_slots,
	s.available_slots_0,
    CASE d.week_day
		WHEN 0 THEN 0
        WHEN 6 THEN
            CASE date_part('h', s.ts_slot_hour)
                WHEN  8 THEN coalesce(cast(hsa.horarios_disponivel08as09 as integer),0)
                WHEN  9 THEN coalesce(cast(hsa.horarios_disponivel09as10 as integer),0)
                WHEN 10 THEN coalesce(cast(hsa.horarios_disponivel10as11 as integer),0)
                WHEN 11 THEN coalesce(cast(hsa.horarios_disponivel11as12 as integer),0)
                WHEN 12 THEN coalesce(cast(hsa.horarios_disponivel12as13 as integer),0)
                WHEN 13 THEN coalesce(cast(hsa.horarios_disponivel13as14 as integer),0)
                WHEN 14 THEN coalesce(cast(hsa.horarios_disponivel14as15 as integer),0)
                WHEN 15 THEN coalesce(cast(hsa.horarios_disponivel15as16 as integer),0)
                WHEN 16 THEN coalesce(cast(hsa.horarios_disponivel16as17 as integer),0)
                WHEN 17 THEN coalesce(cast(hsa.horarios_disponivel17as18 as integer),0)
                WHEN 18 THEN coalesce(cast(hsa.horarios_disponivel18as19 as integer),0)
                WHEN 19 THEN coalesce(cast(hsa.horarios_disponivel19as20 as integer),0)
            END
        ELSE                                       -- Weekdays
		    CASE date_part('h', s.ts_slot_hour)
		        WHEN  8 THEN coalesce(cast(hsa.horarios_disponivel08as09 as integer),0)
                WHEN  9 THEN coalesce(cast(hsa.horarios_disponivel09as10 as integer),0)
                WHEN 10 THEN coalesce(cast(hsa.horarios_disponivel10as11 as integer),0)
                WHEN 11 THEN coalesce(cast(hsa.horarios_disponivel11as12 as integer),0)
                WHEN 12 THEN coalesce(cast(hsa.horarios_disponivel12as13 as integer),0)
                WHEN 13 THEN coalesce(cast(hsa.horarios_disponivel13as14 as integer),0)
                WHEN 14 THEN coalesce(cast(hsa.horarios_disponivel14as15 as integer),0)
                WHEN 15 THEN coalesce(cast(hsa.horarios_disponivel15as16 as integer),0)
                WHEN 16 THEN coalesce(cast(hsa.horarios_disponivel16as17 as integer),0)
		        WHEN 17 THEN coalesce(cast(hsa.horarios_disponivel17as18 as integer),0)
                WHEN 18 THEN coalesce(cast(hsa.horarios_disponivel18as19 as integer),0)
                WHEN 19 THEN coalesce(cast(hsa.horarios_disponivel19as20 as integer),0)
		        ELSE 0
		    END
	END = 1 AS is_allocation_available,
	COALESCE(a.area_deprecated, '-1') AS region_code,
	uwi.workcontract_id,
	s.ts_slot_hour,
	getdate() as ts_load
FROM schedule s
JOIN public.dim_date d
	ON d.sk_date = s.sk_date
JOIN public.dim_agent_region a
	ON a.sk_regions_date = (to_char('{0}'::DATE,'YYYYMMDD')::INTEGER)
		AND a.sk_agent = s.sk_agent_id
JOIN public.dim_user u
    ON s.sk_agent_id = u.dados_agente_id
LEFT JOIN user_workcontract_id uwi
    ON uwi.agent_id = s.sk_agent_id
LEFT JOIN datalake_raw.ebdb_horariosemanalmascara hsa
	ON uwi.workcontract_id = hsa.workcontract_id
        AND hsa.diadasemana = date_part('dow', s.ts_slot_hour)
;