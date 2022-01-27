drop table if exists datalake_clean.ods_fact_photo_job;
create external table datalake_clean.ods_fact_photo_job (
  id_photo_job bigint,
  sk_house_listing bigint,
  sk_region bigint,
  sk_user_cancel bigint,
  sk_user_photographer bigint,
  sk_user_rep bigint,
  job_status varchar(255),
  creation_origin varchar(255),
  photo_shoot_contact_name varchar(255),
  photo_shoot_email varchar(255),
  photo_shoot_phone varchar(255),
  photo_shoot_second_phone varchar(255),
  key_withdraw varchar(255),
  key_comments varchar(255),
  photographer_contract_type varchar(255),
  photographer_problem_reason varchar(255),
  cancel_reason varchar(255),
  user_cancel_type varchar(255),
  flexible_schedule int,
  is_same_day_upload boolean,
  is_anticipated boolean,
  flg_job_on_time boolean,
  approved int,
  confirmed int,
  lockbox int,
  rescheduled boolean,
  sk_date_photographer_accepted bigint,
  sk_date_job_created bigint,
  sk_date_job_issued bigint,
  sk_date_shoot_started bigint,
  sk_date_job_scheduled bigint,
  sk_date_photos_uploaded bigint,
  sk_date_updated bigint,
  sk_date_photographer_start bigint,
  sk_date_user_cancel bigint,
  sk_date_problem_reported bigint,
  creation_to_scheduling_diff_minutes decimal(10,1),
  creation_to_scheduling_diff_hours decimal(10,1),
  creation_to_scheduling_diff_days decimal(10,1)
)
ROW FORMAT SERDE
  'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
STORED AS INPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat'
LOCATION
  's3://dw.s3.data.quintoandar.com.br/public/fact_photo_job'
TBLPROPERTIES (
  'parquet.compress'='SNAPPY')
;