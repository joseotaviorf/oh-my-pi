drop table if exists staging.dim_onboarding_tenant_task;
create table if not exists staging.dim_onboarding_tenant_task (
  sk_task varchar,
  flg_solved boolean,
  score_factor numeric(14,2),
  ts_start timestamp,
  ts_completed timestamp,
  hours_task_start_to_completed numeric(14,2),
  version numeric(14,2),
  origin varchar,
  type varchar,
  titles varchar,
  workgroups varchar,
  dt_partition date
)
;