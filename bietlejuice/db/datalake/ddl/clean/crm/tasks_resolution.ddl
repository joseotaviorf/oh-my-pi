drop table if exists datalake_clean.crm_tasks_resolution;
create external table if not exists datalake_clean.crm_tasks_resolution (
  score_factor string,
  id_rent_flow string,
  actions string,
  ts_start string,
  receiver_name string,
  ts_completed string,
  `comment` string,
  id_origin string,
  id_assignee string,
  score string,
  origin string,
  ts_visit string,
  type string,
  receiver_type string,
  description string,
  phase string,
  ts_silenced_until string,
  id_house string,
  subject string,
  tags string,
  id_opened_by string,
  id_tenant string,
  ts_created string,
  id_negotiation string,
  ts_origin string,
  id_manager string,
  ts_fup string,
  visit_fup string,
  metadata string,
  v string,
  id_owner string,
  id_receiver string,
  id string,
  resolved string,
  action_user_name string,
  id_user_action string,
  ts_action string,
  action_type string,
  ts_task_user_start string,
  ts_task_user_end string,
  task_user_type string,
  task_user_resolve_hours string
)
partitioned by (
  dt string
)
stored as parquet
location 's3://5a-datalake/clean/crm/tasks_resolution/'
;