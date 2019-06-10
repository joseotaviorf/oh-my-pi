WITH schedule AS
(SELECT
	t.agent_id AS sk_agent_id,
	COALESCE(to_char(t.slot_dt::DATE,'YYYYMMDD')::INTEGER, -1) AS sk_date,
	sum(case when coalesce(t.last_change_reason,'') <> 'day off' then cast(t.available_slot_24h AS INTEGER) else 0 end) AS available_slots,
	sum(case when coalesce(t.last_change_reason,'') <> 'day off' then cast(t.specific_slot AS INTEGER) else 0 end) AS available_slots_0
 FROM agent.agents_slots t
 WHERE DATE(t.slot_dt) BETWEEN DATE('{0}') AND (DATE('{0}') + INTERVAL '21 days') and t.agent_type = 'SessaoFotos'
GROUP BY 1, 2
)
SELECT
	s.sk_agent_id,
	u.dados_fotografo_id,
	s.sk_date,
	s.available_slots,
	s.available_slots_0,
	CASE d.week_day
		WHEN 0 THEN 0	-- Sunday
		WHEN 6 THEN 36	-- Saturday
		ELSE 32			-- Other days
	END AS total_slots,
	COALESCE(a.area_deprecated, '-1') AS area,
	COALESCE(a.sk_agent_region, -1) AS sk_agent_region,
	getdate() as ts_load
FROM schedule s
JOIN public.dim_date d
	ON d.sk_date = s.sk_date
LEFT JOIN public.dim_agent_region a
	ON a.sk_regions_date = s.sk_date
		AND a.sk_agent = s.sk_agent_id
LEFT JOIN public.dim_user u
    ON s.sk_agent_id = u.dados_agente_id
ORDER BY s.sk_date;