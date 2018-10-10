with actions_prev as (
  select
    *,
    regexp_extract_all(actions, '{[^}]+[^,]+[^{]+}') as action_array
  from datalake_clean.crm_tasks
  where dt = '__PARTITION_DATE__'
),
actions as (
  select distinct
    ct.*,
    cast(json_extract(a.action, '$.username') as varchar) as action_user_name,
    cast(json_extract(a.action, '$.userid') as varchar) as id_user_action,
    cast(regexp_extract(cast(json_extract(a.action, '$.date') as varchar), '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp) as dt_action,
    cast(json_extract(a.action, '$.type') as varchar) as action_type
  from actions_prev ct
  cross join unnest(action_array) as a (action)
)
select
  links,
  score_factor,
  id_rent_flow,
  actions,
  dt_start,
  receiver_name,
  dt_completed,
  comment,
  id_origin,
  id_assignee,
  score,
  origin,
  dt_visit,
  type,
  receiver_type,
  description,
  phase,
  dt_silenced_until,
  id_house,
  subject,
  tags,
  id_opened_by,
  id_tenant,
  dt_created,
  id_negotiation,
  data_origin,
  id_manager,
  fup_date,
  fup_visit,
  metadata,
  version,
  id_owner,
  id_receiver,
  id,
  solved,
  action_user_name,
  id_user_action,
  dt_action,
  action_type,
  lag(dt_action) over (partition by id order by dt_action) as dt_task_user_start,
  dt_action as dt_task_user_end,
  action_type as task_user_type,
  if(action_user_name is null, null,
    round(date_diff('second', lag(dt_action) over (partition by id order by dt_action), dt_action) / 3600.0, 1)) as task_user_resolve_hours
from actions
;
