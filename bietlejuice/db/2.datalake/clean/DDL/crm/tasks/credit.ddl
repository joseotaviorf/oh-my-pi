drop table if exists datalake_clean.crm_tasks_credit;
create external table if not exists datalake_clean.crm_tasks_credit (
  id_origin bigint,
  dt_origin string,
  id_assignee bigint,
  solved boolean,
  score_factor double,
  actions string,
  dt_start string,
  version int,
  origin string,
  id_receiver bigint,
  id string,
  type string,
  dt_completed string,
  metadata string
)
partitioned by (
  dt string
)
stored as parquet
location 's3://5a-datalake/clean/crm/tasks/credit'
;