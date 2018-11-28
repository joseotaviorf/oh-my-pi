drop table if exists staging.fact_photo_job_tasks;
create table if not exists staging.fact_photo_job_tasks (
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
  sk_house_listing bigint,
  sk_house_owner bigint,
  sk_photo_job bigint,
  sk_user_sales_rep bigint,
  dt_partition date
)
;