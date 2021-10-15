WITH schedule AS (
SELECT
	t.id_agent AS sk_agent,
	COALESCE(to_char(t.ts_slot::DATE,'YYYYMMDD')::INTEGER, -1) AS sk_slot_date,
  date_trunc('h', t.ts_slot) AS ts_slot_hour,
	sum(case when coalesce(t.last_change_reason,'') <> 'day off' then cast(t
.is_available_slot_24h AS INTEGER) else 0 end) AS allocated_slots,
	sum(case when coalesce(t.last_change_reason,'') <> 'day off' then cast(t
.is_available_specific_slot AS INTEGER) else 0 end) AS allocated_slots_0
FROM datalake_ebdb_agents_prod.agents_slots t
WHERE DATE(t.ts_slot) BETWEEN DATE('{0}') AND (DATE('{0}') + INTERVAL '21 days') and t.agent_type = 'SessaoFotos'
GROUP BY 1, 2, 3
),
agent_contract_rank AS (
SELECT
		*,
		RANK() OVER (PARTITION BY agent_id ORDER BY "timestamp" DESC) AS "rank"
	FROM agent.agent_contract
	WHERE "timestamp" <= CAST('{0}' AS TIMESTAMP)
)
SELECT
	s.sk_agent,
	s.sk_slot_date,
  to_char(s.ts_slot_hour,'YYYYMMDDHH24')::bigint as sk_slot_date_hour,
	COALESCE(a.sk_agent_region, -1) AS sk_agent_region,
	CAST(CAST(s.sk_slot_date AS VARCHAR) + CAST(s.sk_agent AS VARCHAR) AS BIGINT) as sk_slot_date_agent,
	COALESCE(acr.workcontract_id, -1) as id_work_contract,
	u.dados_fotografo_id as id_dados_fotografo,
	s.ts_slot_hour,
	s.allocated_slots,
	s.allocated_slots_0,
  CASE date_part('h', s.ts_slot_hour)
		WHEN  8 THEN coalesce(cast(hsm.horarios_disponivel08as09 as integer),0)
		WHEN  9 THEN coalesce(cast(hsm.horarios_disponivel09as10 as integer),0)
		WHEN 10 THEN coalesce(cast(hsm.horarios_disponivel10as11 as integer),0)
		WHEN 11 THEN coalesce(cast(hsm.horarios_disponivel11as12 as integer),0)
		WHEN 12 THEN coalesce(cast(hsm.horarios_disponivel12as13 as integer),0)
		WHEN 13 THEN coalesce(cast(hsm.horarios_disponivel13as14 as integer),0)
		WHEN 14 THEN coalesce(cast(hsm.horarios_disponivel14as15 as integer),0)
		WHEN 15 THEN coalesce(cast(hsm.horarios_disponivel15as16 as integer),0)
		WHEN 16 THEN coalesce(cast(hsm.horarios_disponivel16as17 as integer),0)
		WHEN 17 THEN coalesce(cast(hsm.horarios_disponivel17as18 as integer),0)
		WHEN 18 THEN coalesce(cast(hsm.horarios_disponivel18as19 as integer),0)
		WHEN 19 THEN coalesce(cast(hsm.horarios_disponivel19as20 as integer),0)
		ELSE 0
	END = 1 AS is_allocation_available,
	COALESCE(a.area_deprecated, '-1') AS area,
	getdate() as ts_load
FROM schedule s
JOIN public.dim_date d
	ON d.sk_date = s.sk_slot_date
JOIN public.dim_agent_region a
	ON a.sk_regions_date = COALESCE(to_char('{0}'::DATE,'YYYYMMDD')::INTEGER, -1)
		AND a.sk_agent = s.sk_agent
JOIN public.dim_user u
    ON s.sk_agent = u.dados_agente_id
LEFT JOIN agent_contract_rank acr
    ON acr.agent_id = s.sk_agent AND acr."rank" = 1
LEFT JOIN datalake_ebdb_raw_prod.horariosemanalmascara hsm
    ON hsm.workcontract_id  = acr.workcontract_id and mod(hsm.diadasemana, 7) = mod(d.week_day, 7)
ORDER BY s.sk_slot_date
;