drop table if exists datalake_clean.ods_dim_photo_job;
create external table if not exists datalake_clean.ods_dim_photo_job (
    sk_photo_job string,
	id string,
	imovel_id string,
	rep_id string,
	job_status string,
	creation_origin string,
	flexible_schedule string,
	is_same_day_upload string,
	is_anticipated string,
	dt_photographer_accepted string,
	dt_job_created string,
	dt_job_issued string,
	dt_shoot_started string,
	dt_job_scheduled string,
	dt_photos_uploaded string,
	dt_updated string,
	scheduling_instructions string,
	photo_shoot_contact_name string,
	photo_shoot_email string,
	photo_shoot_phone string,
	photo_shoot_second_phone string,
	approved string,
	confirmed string,
	lockbox string,
	key_withdraw string,
	key_comments string,
	photographer_id string,
	photographer_name string,
	photographer_email string,
	dt_photographer_start string,
	photographer_contract_type string,
	job_problem_reason string,
	cancel_reason string,
	cancel_reason_detailed string,
	user_cancel_dt string,
	user_cancel_id string,
	user_cancel_name string,
	user_cancel_email string,
	user_cancel_type string,
	rescheduled string,
	job_scheduling_reason string,
	creation_to_scheduling_diff_minutes string,
	creation_to_scheduling_diff_hours string,
	creation_to_scheduling_diff_days string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/clean/ods/dim_photo_job'
tblproperties (
  'skip.header.line.count' = '1'
)
;