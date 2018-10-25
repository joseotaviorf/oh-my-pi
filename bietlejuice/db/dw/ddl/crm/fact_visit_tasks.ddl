drop table if exists crm.fact_visit_tasks;
create table if not exists crm.fact_visit_tasks (
  sk_task varchar,
  sk_receiver bigint,
  sk_start_date integer,
  sk_completed_date integer,
  sk_origin bigint,
  sk_assignee bigint,
  action_user_name varchar,
  sk_user_action bigint,
  sk_action_date integer,
  ts_action timestamp,
  action_type varchar,
  sk_task_action_start_date integer,
  ts_task_action_start timestamp,
  sk_task_action_end_date integer,
  ts_task_action_end timestamp,
  task_action_type varchar,
  task_user_action_resolve_hours numeric(14,2),
  sk_booking bigint,
  sk_house_listing bigint,
  ts_load timestamp
)
;