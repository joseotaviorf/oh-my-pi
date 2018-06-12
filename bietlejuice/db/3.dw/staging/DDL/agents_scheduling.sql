drop table if exists staging.agents_scheduling;
create table if not exists staging.agents_scheduling (
	agent_id varchar,
	agent_name varchar,
	planner_status integer,
	history_status integer,
	slot_dt timestamp,
	realized_schedule varchar,
	available_slots_96 integer,
	available_slots_0 integer
)
;