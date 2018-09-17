drop table if exists crm.dim_visit_task;
create table if not exists crm.dim_visit_task (
  sk_task varchar,
  flg_solved boolean,
  score_factor numeric(14,2),
  dt_start timestamp,
  dt_completed timestamp,
  version numeric(14,2),
  origin varchar,
  type varchar,
  dt_timestamp timestamp
)
;