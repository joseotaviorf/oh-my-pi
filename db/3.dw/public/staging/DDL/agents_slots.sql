create table staging.agents_slots (
	agent_id bigint,
	last_weekly_update timestamp,
	last_specific_update timestamp,
	slot_dt timestamp,
	dow integer,
	slot_number integer,
	specific_slot integer,
	time_window_slot integer,
	agent_slot integer,
	has_visit bool,
	change_reason varchar(100),
	history_status integer,
	planner_status integer
)