drop table if exists crm.dim_credit_tasks;
create table if not exists crm.dim_credit_tasks (
  sk_credit_task varchar,
  id_origin bigint,
  id_assignee bigint,
  flg_solved boolean,
  score_factor numeric(14,2),
  dt_task_start timestamp,
  dt_task_end timestamp,
  version integer,
  origin varchar,
  id_receiver bigint,
  type varchar
);