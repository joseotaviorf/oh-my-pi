drop table if exists datalake_clean.crm_task_resolution_history;
create external table if not exists datalake_clean.crm_task_resolution_history (
  score_factor string,
  id_rent_flow string,
  histories string,
  ts_start string,
  receiver_name string,
  ts_completed string,
  comment string,
  id_origin string,
  id_assignee string,
  id_user_action string,
  action_user_name string,
  score string,
  origin string,
  ts_visit string,
  type string,
  receiver_type string,
  description string,
  phase string,
  ts_silenced_until string,
  analyst_started_list string,
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
  id_action string,
  id_task string,
  resolved string,
  ts_action string,
  status string,
  ts_task_user_start string,
  ts_task_user_end string,
  task_user_type string,
  task_user_resolve_hours string
)
partitioned by (
  dt string
)
stored as parquet
location 's3://5a-datalake/clean/crm/task_resolution_history/'
;
