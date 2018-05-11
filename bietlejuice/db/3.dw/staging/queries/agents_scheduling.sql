select
	u.id as agent_id,
	u.nome as agent_name,
	t.planner_status,
	t.history_status,
	t.slot_dt,
	case
		when t.slot_dt >= current_date
			then 'Open Schedule'
		else 'Realized Schedule'
	end as realized_schedule,
	sum(cast(t.available_slot as integer)) as available_slots
from staging.agents_slots t
left join datalake_raw.ebdb_usuario u
	on u.dadosagente_id = t.agent_id
group by 1, 2, 3, 4, 5, 6
;