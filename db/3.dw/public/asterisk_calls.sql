DROP TABLE IF EXISTS public.asterisk_calls;
CREATE TABLE IF NOT EXISTS public.asterisk_calls (
	id VARCHAR(255),
	call_state VARCHAR(255),
	caller_number VARCHAR(255),
	agent_extension VARCHAR(255),
	agent_name VARCHAR(255),
	ura_name VARCHAR(255),
	queue_id VARCHAR(255),
	queue_name VARCHAR(255),
	available_agents INTEGER,
	ura_duration INTEGER,
	waiting_duration INTEGER,
	call_duration INTEGER,
	call_start TIMESTAMP WITHOUT TIME ZONE,
	ura_change TIMESTAMP WITHOUT TIME ZONE,
	queue_enter TIMESTAMP WITHOUT TIME ZONE,
	answer_time TIMESTAMP WITHOUT TIME ZONE,
	transfer_time TIMESTAMP WITHOUT TIME ZONE,
	hangup_time TIMESTAMP WITHOUT TIME ZONE,
	survey_end_time TIMESTAMP WITHOUT TIME ZONE,
	problem_solved_question INTEGER,
	agent_score_question INTEGER
);