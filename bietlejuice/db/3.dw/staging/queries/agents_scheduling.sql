select
	u.id as agent_id,
	u.nome as agent_name,
	t.planner_status,
	t.history_status,
	date(t.slot_dt) as slot_dt,
	case
		when t.slot_dt >= current_date
			then 'Open Schedule'
		else 'Realized Schedule'
	end as realized_schedule,
	sum(cast(t.available_slot as integer)) as available_slots_96,
	sum(cast(t.specific_slot as integer)) as available_slots_0
from staging.agents_slots t
join datalake_raw.ebdb_usuario u
	on u.dadosagente_id = t.agent_id
where date(t.slot_dt) = date('{}')
group by 1, 2, 3, 4, 5, 6
;