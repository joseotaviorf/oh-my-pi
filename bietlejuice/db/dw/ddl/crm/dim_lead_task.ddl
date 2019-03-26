drop table if exists crm.dim_lead_task;
create table if not exists crm.dim_lead_task (
  sk_task varchar,
  flg_solved boolean,
  score_factor numeric(14,2),
  ts_start timestamp,
  ts_completed timestamp,
  ts_silenced_until timestamp,
  hours_task_start_to_completed numeric(14,2),
  version numeric(14,2),
  origin varchar,
  type varchar,
  titles varchar(2000),
  workgroups varchar,
  ts_load timestamp
)
;