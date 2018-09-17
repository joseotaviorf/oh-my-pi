drop table if exists datalake_clean.crm_tasks_resolution;
create external table if not exists datalake_clean.crm_tasks_resolution (
  links string,
  score_factor double,
  id_rent_flow double,
  actions string,
  dt_start string,
  receiver_name string,
  dt_completed string,
  comment string,
  id_origin double,
  id_assignee double,
  score string,
  origin string,
  dt_visit string,
  type string,
  receiver_type string,
  description string,
  phase string,
  dt_silenced_until string,
  id_house double,
  subject string,
  tags string,
  id_opened_by double,
  id_tenant double,
  dt_created string,
  id_negotiation double,
  data_origin string,
  id_manager string,
  fup_date string,
  fup_visit string,
  metadata string,
  version double,
  id_owner double,
  id_receiver double,
  id string,
  solved boolean,
  action_user_name string,
  id_user_action string,
  dt_action string,
  action_type string,
  dt_task_user_start string,
  dt_task_user_end string,
  task_user_type string,
  task_user_resolve_hours double
)
partitioned by (
  dt string
)
stored as parquet
location 's3://5a-datalake/clean/crm/tasks_resolution/'
;