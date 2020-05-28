with actions_prev as (
select distinct
    tasks.score_factor,
    tasks.id_rent_flow,
    histories.histories,
    tasks.ts_start,
    tasks.receiver_name,
    tasks.ts_completed,
    tasks."comment",
    tasks.id_origin,
    tasks.id_assignee,
    tasks.score,
    tasks.origin,
    tasks.ts_visit,
    tasks.type,
    tasks.receiver_type,
    tasks.description,
    tasks.phase,
    tasks.ts_silenced_until,
    tasks.analyst_started_list,
    tasks.id_house,
    tasks.subject,
    tasks.tags,
    tasks.id_opened_by,
    tasks.id_tenant,
    tasks.ts_created,
    tasks.id_negotiation,
    tasks.ts_origin,
    tasks.id_manager,
    tasks.ts_fup,
    tasks.visit_fup,
    tasks.metadata,
    tasks.v,
    tasks.id_owner,
    tasks.id_receiver,
    tasks.id,
    tasks.resolved,
    regexp_extract_all(histories.histories, '{[^}]+[^,]+[^{]+}') as histories_array,
    regexp_extract_all(tasks.actions, '{[^}]+[^,]+[^{]+}') as action_array
from datalake_clean.crm_tasks tasks
join datalake_clean.crm_task_status_histories histories
   on tasks.id = histories.id
where cardinality(regexp_extract_all(histories.histories, '{[^}]+[^,]+[^{]+}')) <= 500
and tasks.dt = '__PARTITION_DATE__'
),
history as (
  select
    ct.*,
    cast(json_extract(a.history, '$._id') as varchar) as id_action,
    cast(json_extract(a.history, '$.status') as varchar) as status,
    cast(regexp_extract(json_format(json_extract(a.history, '$.date')), '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp) as ts_action,
    replace(json_format(json_extract(a.history, '$.type')), '"') as action_type
  from actions_prev ct
  cross join unnest(histories_array) as a (history)
),
actions as (
  select
    history.*,
    replace(json_format(json_extract(a.action, '$.userName')), '"') as action_user_name,
    json_format(json_extract(a.action, '$.userId')) as id_user_action
  from actions_prev ct
  cross join unnest(action_array) as a (action)
  join history
    on history.id = ct.id
)
select
  score_factor,
  id_rent_flow,
  histories,
  ts_start,
  REPLACE(receiver_name, ',', '') as receiver_name,
  ts_completed,
  "comment",
  id_origin,
  id_assignee,
  id_user_action,
  action_user_name,
  score,
  origin,
  ts_visit,
  type,
  receiver_type,
  description,
  phase,
  ts_silenced_until,
  analyst_started_list,
  id_house,
  subject,
  tags,
  id_opened_by,
  id_tenant,
  ts_created,
  id_negotiation,
  ts_origin,
  id_manager,
  ts_fup,
  visit_fup,
  metadata,
  v,
  id_owner,
  id_receiver,
  id_action,
  id as id_task,
  resolved,
  ts_action,
  status,
  lag(ts_action) over (partition by id order by ts_action) as ts_task_user_start,
  ts_action as ts_task_user_end,
  action_type as task_user_type,
  if(action_user_name is null, null,
    round(date_diff('second', lag(ts_action) over (partition by id order by ts_action), ts_action) / 3600.0, 1)) as task_user_resolve_hours
from actions
;