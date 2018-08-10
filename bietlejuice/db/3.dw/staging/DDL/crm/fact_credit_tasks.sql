drop table if exists staging.fact_credit_tasks;
create table if not exists staging.fact_credit_tasks (
  sk_task varchar,
  sk_receiver bigint,
  sk_start_date integer,
  sk_completed_date integer,
  sk_origin bigint,
  sk_assignee bigint,
  action_user_name varchar,
  sk_user_action bigint,
  sk_action_date integer,
  dt_action timestamp,
  action_type varchar,
  sk_task_user_start_date integer,
  dt_task_user_start timestamp,
  sk_task_user_end_date integer,
  dt_task_user_end timestamp,
  task_user_type varchar,
  task_user_resolve_hours numeric(14,2),
  dt_partition date
)
;