drop table if exists agent.agents_scheduling;
create table if not exists agent.agents_scheduling (
	agent_id varchar,
	agent_name varchar,
	planner_status integer,
	history_status integer,
	slot_dt timestamp,
	realized_schedule varchar,
	available_slots_0 integer,
	available_slots_24 integer,
	available_slots_96 integer
)
;