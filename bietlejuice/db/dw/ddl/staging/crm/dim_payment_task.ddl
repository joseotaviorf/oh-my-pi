drop table if exists staging.dim_payment_task;
create table if not exists staging.dim_payment_task (
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
  dt_partition date
)
;