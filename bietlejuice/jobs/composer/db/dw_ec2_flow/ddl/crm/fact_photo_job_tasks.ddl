drop table if exists crm_20211103.fact_photo_job_tasks;
create table if not exists crm_20211103.fact_photo_job_tasks (
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
  sk_task_user_start_date integer,
  ts_task_user_start timestamp,
  sk_task_user_end_date integer,
  ts_task_user_end timestamp,
  task_user_type varchar,
  task_user_resolve_hours numeric(14,2),
  sk_house_listing bigint,
  sk_house_owner bigint,
  sk_photo_job bigint,
  sk_user_sales_rep bigint,
  ts_load timestamp
)
;