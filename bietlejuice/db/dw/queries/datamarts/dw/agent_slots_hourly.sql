SELECT
	agent_id,
	to_char(slot_dt, 'YYYYMMDD') as sk_date,
	DATE_PART(HOUR, slot_dt)::integer as hour,
	SUM(COALESCE(available_slot,0)) as available_slots,
	SUM(COALESCE(available_slot_24h,0)) as available_slots_24h
FROM
	agent.agents_slots
WHERE date(slot_dt) >= date('2018-10-01')
GROUP BY 1,2,3