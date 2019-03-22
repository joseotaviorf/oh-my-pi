WITH schedule AS
(SELECT
	t.agent_id AS sk_agent_id,
	COALESCE(to_char(t.slot_dt::DATE,'YYYYMMDD')::INTEGER, -1) AS sk_date,
	sum(case when coalesce(t.last_change_reason,'') <> 'day off' then cast(t.available_slot_24h AS INTEGER) else 0 end) AS available_slots,
	sum(case when coalesce(t.last_change_reason,'') <> 'day off' then cast(t.specific_slot AS INTEGER) else 0 end) AS available_slots_0
 FROM agent.agents_slots_tmp t --change to real name
 WHERE DATE(t.slot_dt) = DATE('{0}') and t.agent_type = 'SessaoFotos'
GROUP BY 1, 2
)
SELECT
	s.*,
	CASE d.week_day
		WHEN 0 THEN 0	-- Sunday
		WHEN 6 THEN 36	-- Saturday
		ELSE 32			-- Other days
	END AS total_slots,
	COALESCE(a.area, '-1') AS area,
	COALESCE(a.sk_agent_region, -1) AS sk_agent_region,
	CAST(CAST(s.sk_date AS VARCHAR) + CAST(s.sk_agent_id AS VARCHAR) AS BIGINT) as sk_slot_date_agent,
	getdate() as dt_timestamp
FROM schedule s
JOIN public.dim_date d
	ON d.sk_date = s.sk_date
LEFT JOIN public.dim_agent_region a
	ON a.sk_regions_date = s.sk_date
		AND a.sk_agent = s.sk_agent_id
ORDER BY s.sk_date;