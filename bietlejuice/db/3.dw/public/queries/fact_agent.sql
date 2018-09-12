WITH schedule AS
(SELECT
	t.agent_id AS sk_agent_id,
	COALESCE(to_char(t.slot_dt::DATE,'YYYYMMDD')::INTEGER, -1) AS sk_date,
	sum(case when t.available_slot = 1 AND coalesce(t.last_change_reason,'') <> 'day off' then cast(t.available_slot_24h AS INTEGER) else 0 end) AS available_slots,
	sum(case when t.available_slot = 1 AND coalesce(t.last_change_reason,'') <> 'day off' then cast(t.specific_slot AS INTEGER) else 0 end) AS available_slots_0
 FROM staging.agents_slots t
 WHERE DATE(t.slot_dt) = DATE('{0}')
GROUP BY 1, 2
),
first_visits AS
(SELECT
	id_agent,
	min(dt_scheduling) as dt_first_visit
 FROM public.dim_booking db
 WHERE db.type = 'Visita'
 GROUP BY id_agent
),
available_next_days AS
(SELECT
	t.agent_id AS sk_agent_id,
	case when sum(case when t.available_slot = 1 AND coalesce(t.last_change_reason,'') <> 'day off' then cast(t.available_slot_24h AS INTEGER) end) > 0 then 1 else 0 end AS flg_available_next_daysgit
 FROM staging.agents_slots t
 WHERE DATE(t.slot_dt) BETWEEN DATEADD(DAY, 1, DATE('{0}')) AND DATEADD(DAY, 4, DATE('{0}'))
GROUP BY 1
)
SELECT
	s.*,
	CASE d.week_day
		WHEN 0 THEN 0	-- Sunday
		WHEN 6 THEN 20	-- Saturday
		ELSE 36			-- Other days
	END AS total_slots,
	COALESCE(a.area, '-1') AS area,
	COALESCE(a.sk_agent_region, -1) AS sk_agent_region,
	CAST(CAST(s.sk_date AS VARCHAR) + CAST(s.sk_agent_id AS VARCHAR) AS BIGINT) as sk_slot_date_agent,
	dt_first_visit,
	coalesce(av.flg_available_next_days, 0) as flg_available_next_days,
	getdate() as dt_timestamp
FROM schedule s
JOIN public.dim_date d
	ON d.sk_date = s.sk_date
LEFT JOIN public.dim_agent_region a
	ON a.sk_regions_date = s.sk_date
		AND a.sk_agent = s.sk_agent_id
LEFT JOIN first_visits fv
	ON fv.id_agent = s.sk_agent_id
LEFT JOIN available_next_days av
    ON av.sk_agent_id = s.sk_agent_id
ORDER BY s.sk_date;