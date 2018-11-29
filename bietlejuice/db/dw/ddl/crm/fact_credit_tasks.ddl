drop table if exists crm.fact_credit_tasks;
create table if not exists crm.fact_credit_tasks (
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
  sk_proposal bigint,
  sk_house_listing bigint,
  sk_house_owner bigint,
  sk_proponent bigint,
  ts_load timestamp
)
;