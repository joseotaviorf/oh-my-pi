drop table if exists crm_20211103.dim_payment_task;
create table if not exists crm_20211103.dim_payment_task (
  sk_task varchar primary key,
  flg_solved boolean,
  tenant_refund_status varchar,
  score_factor numeric(14,2),
  ts_start timestamp,
  ts_completed timestamp,
  ts_silenced_until timestamp,
  hours_task_start_to_completed numeric(14,2),
  version numeric(14,2),
  origin varchar,
  type varchar,
  is_task_auto_completed boolean,
  description varchar(5000),
  subject varchar(100), 
  titles varchar,
  workgroups varchar,
  ts_load timestamp
)
;