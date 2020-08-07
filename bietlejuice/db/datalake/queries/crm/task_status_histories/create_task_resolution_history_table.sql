with tasks as (
	select distinct
		tasks.id as id_task,
		histories.id as id_history,
		tasks.id_house,
		tasks.id_rent_flow,
		tasks.id_origin,
		tasks.id_assignee,
		tasks.id_opened_by,
		tasks.id_tenant,
		tasks.id_negotiation,
		tasks.id_manager,
		tasks.id_owner,
		tasks.id_receiver,
		tasks.v,
		tasks.type,
		tasks.score_factor,
		tasks.receiver_name,
		tasks."comment",
		tasks.score,
		tasks.origin,
		tasks.receiver_type,
		tasks.description,
		tasks.phase,
		tasks.analyst_started_list,
		tasks.subject,
		tasks.tags,
		tasks.visit_fup,
		tasks.metadata,
		tasks.resolved,
		tasks.ts_created,
		tasks.ts_start,
		tasks.ts_completed,
		tasks.ts_visit,
		tasks.ts_silenced_until,
		tasks.ts_origin,
		tasks.ts_fup,
		regexp_extract_all(histories.histories, '{[^}]+[^,]+[^{]+}') as histories_array,
		regexp_extract_all(tasks.actions, '{[^}]+[^,]+[^{]+}') as action_array
	from
		datalake_clean.crm_tasks tasks
	left join
		datalake_clean.crm_task_status_histories histories
	   		on tasks.id = histories.id
	   		and cardinality(regexp_extract_all(histories.histories, '{[^}]+[^,]+[^{]+}')) <= 500
	   		and histories.dt = '__PARTITION_DATE__'
	where
		cardinality(regexp_extract_all(tasks.actions, '{[^}]+[^,]+[^{]+}')) <= 500
		and tasks.dt = '__PARTITION_DATE__'
),
history as (
	select distinct
		*,
		json_extract_scalar(a.action, '$._id') as id_action,
		json_extract_scalar(a.action, '$.userId') as id_user_action,
		json_extract_scalar(a.action, '$.userName') as action_user_name,
		json_extract_scalar(a.action, '$.action') as action_type,
		json_extract_scalar(a.action, '$.reason') as action_reason,
		json_extract_scalar(a.action, '$.status') as task_status,
		cast(regexp_extract(json_extract_scalar(a.action, '$.date'), '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp) as ts_action
	from
		tasks
	cross join
		unnest(histories_array) as a (action)
	where
		id_history is not null
),
actions as (
	select distinct
		*,
		json_extract_scalar(a.action, '$._id') as id_action,
		json_extract_scalar(a.action, '$.userId') as id_user_action,
		json_extract_scalar(a.action, '$.userName') as action_user_name,
		json_extract_scalar(a.action, '$.type') as action_type,
		NULL as action_reason,
		NULL as task_status,
		cast(regexp_extract(json_extract_scalar(a.action, '$.date'), '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp) as ts_action
	from
		tasks
	cross join
		unnest(action_array) as a (action)
	where
		id_history is null
),
history_actions as (
	select * from history
	union all
	select * from actions
)
select
	id_task,
	id_action,
	id_assignee,
	id_user_action,
	id_house,
	id_rent_flow,
	id_origin,
	id_opened_by,
	id_tenant,
	id_negotiation,
	id_manager,
	id_owner,
	id_receiver,
	type,
	action_user_name,
	action_type,
	action_reason,
	task_status,
	resolved,
	tags,
	metadata,
	score_factor,
	REPLACE(receiver_name, ',', '') as receiver_name,
	"comment",
	score,
	origin,
	receiver_type,
	description,
	phase,
	analyst_started_list,
	subject,
	visit_fup,
	v,
	if(action_user_name is null, null,
	    round(date_diff('second', lag(ts_action) over (partition by id_task order by ts_action), ts_action) / 3600.0, 1)) as task_user_resolve_hours,
	ts_action,
	lag(ts_action) over (partition by id_task order by ts_action) as ts_previous_action,
	ts_created,
	ts_start,
	ts_completed,
	ts_visit,
	ts_silenced_until,
	ts_origin,
	ts_fup
from
	history_actions
;