drop table if exists crm.fact_credit_tasks;
create table if not exists crm.fact_credit_tasks (
  sk_credit_task varchar,
  sk_task_start_date integer,
  sk_task_end_date integer,
  sk_task_user bigint,
  sk_task_user_start_date integer,
  sk_task_user_end_date integer,
  task_user_type varchar(50),
  task_user_resolve_hours numeric(14,2)
);