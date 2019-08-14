drop table if exists datalake_clean.ods_fact_photo_job;
create external table datalake_clean.ods_fact_photo_job (
  id_photo_job string,
  sk_house_listing string,
  sk_region string,
  sk_user_cancel string,
  sk_user_photographer string,
  sk_user_rep string,
  job_status string,
  creation_origin string,
  flexible_schedule string,
  same_day_listing string,
  flg_job_on_time string,
  sk_date_photographer_accepted string,
  sk_date_job_created string,
  sk_date_job_issued string,
  sk_date_shoot_started string,
  sk_date_job_scheduled string,
  sk_date_photos_uploaded string,
  sk_date_updated string,
  sk_date_photographer_start string,
  sk_date_user_cancel string,
  photo_shoot_contact_name string,
  photo_shoot_email string,
  photo_shoot_phone string,
  photo_shoot_second_phone string,
  approved string,
  confirmed string,
  lockbox string,
  key_withdraw string,
  key_comments string,
  photographer_contract_type string,
  job_problem_reason string,
  cancel_reason string,
  rescheduled string,
  user_cancel_type string,
  creation_to_scheduling_diff_minutes string,
  creation_to_scheduling_diff_hours string,
  creation_to_scheduling_diff_days string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/ods/photo_job'
tblproperties (
  'skip.header.line.count' = '1'
)
;