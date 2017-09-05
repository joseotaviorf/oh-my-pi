select
	calls.id,
	calls.call_state,
	calls.caller as caller_number,
	case calls.agent_extension when 'null' then null else calls.agent_extension end as agent_extension,
	case calls.agent_extension
		when 'null' then null
		when '8332' then 'Leandro Assumpcao' -- hardcoded for early calls
		else coalesce(calls.agent_name, config.agent_name)
	end as agent_name,
	calls.ura_name,
	case calls.call_state
		when 'Answered' then calls.queue_id
		else null
	end as queue_id,
	case calls.call_state
		when 'Answered' then calls.queue_name
		else null
	end as queue_name,
	case calls.available_agents when 'null' then null else calls.available_agents end as available_agents,
	case calls.ura_duration when 'null' then null else calls.ura_duration end as ura_duration,
	case calls.waiting_duration when 'null' then null else calls.waiting_duration end as waiting_duration,
	case calls.call_duration when 'null' then null else calls.call_duration end as call_duration,
	case calls.call_start when 'null' then null else calls.call_start end as call_start,
	case calls.ura_change when 'null' then null else calls.ura_change end as ura_change,
	case calls.queue_enter when 'null' then null else calls.queue_enter end as queue_enter,
	case calls.answer_time when 'null' then null else calls.answer_time end as answer_time,
	case calls.transfer_time when 'null' then null else calls.transfer_time end as transfer_time,
	case calls.hangup_time when 'null' then null else calls.hangup_time end as hangup_time,
	scores."timestamp" as survey_end_time,
	scores.question1 as problem_solved_question,
	scores.question2 as agent_score_question
from
	datalake_raw.asterisk_calls calls
left join
	datalake_raw.asterisk_surveys scores
	on calls.id = scores.unique_id
left join
	(
		select agent_extension, agent_name
		from
		datalake_raw.asterisk_config
		group by agent_extension, agent_name
	) config
	on calls.agent_extension = config.agent_extension