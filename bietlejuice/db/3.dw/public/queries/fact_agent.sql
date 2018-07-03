WITH schedule AS
(select
	t.agent_id as sk_agent_id,
	coalesce(to_char(t.slot_dt::DATE,'YYYYMMDD')::integer, -1) as sk_date,
	sum(cast(t.available_slot as integer)) as available_slots,
	sum(cast(t.specific_slot as integer)) as available_slots_0
 from staging.agents_slots t
 where date(t.slot_dt) = date('{}')
group by 1, 2
)
SELECT
	s.*,
	CASE d.week_day
		WHEN 6 THEN 20	-- Saturday
		ELSE 36			-- Other days
	END as total_slots,
	COALESCE(a.area, '-1') AS area,
	COALESCE(a.sk_agentregion, -1) as sk_agentregion,
	CAST(CAST(s.sk_date AS VARCHAR) + CAST(sk_agent_id AS VARCHAR) AS BIGINT)
FROM schedule s
LEFT JOIN public.dim_date d
	ON d.sk_date = s.sk_date
LEFT JOIN public.dim_agent_region a
	ON a.sk_regions_date = s.sk_date
		AND a.sk_agent = s.sk_agent_id
ORDER BY s.sk_date;