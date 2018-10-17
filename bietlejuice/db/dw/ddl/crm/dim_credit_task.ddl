drop table if exists crm.dim_credit_task;
create table if not exists crm.dim_credit_task (
  sk_task varchar,
  flg_solved boolean,
  score_factor numeric(14,2),
  dt_start timestamp,
  dt_completed timestamp,
  hours_task_start_to_completed numeric(14,2),
  version numeric(14,2),
  origin varchar,
  type varchar,
  title varchar,
  id_workgroup varchar,
  dt_timestamp timestamp
)
;