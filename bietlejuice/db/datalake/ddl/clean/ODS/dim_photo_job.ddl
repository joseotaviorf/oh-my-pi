drop table if exists datalake_clean.ods_dim_photo_job;
create external table if not exists datalake_clean.ods_dim_photo_job (
    sk_photo_job bigint,
    id bigint,
    imovel_id bigint,
    rep_id bigint,
    photographer_id bigint,
    user_cancel_id bigint,
    job_status varchar(255),
    creation_origin varchar(20),
    scheduling_instructions varchar,
    photo_shoot_contact_name varchar(255),
    photo_shoot_email varchar(255),
    photo_shoot_phone varchar(20),
    photo_shoot_second_phone varchar(20),
    key_withdraw varchar(255),
    key_comments varchar(255),
    photographer_name varchar(255),
    photographer_email varchar(255),
    photographer_contract_type varchar(255),
    photographer_problem_reason varchar(255),
    user_sender_type varchar(255),
    cancel_reason varchar(255),
    cancel_reason_detailed varchar(512),
    user_cancel_name varchar(255),
    user_cancel_email varchar(255),
    user_cancel_type varchar(255),
    flexible_schedule int,
    approved int,
    confirmed int,
    lockbox int,
    rescheduled boolean,
    is_same_day_upload boolean,
    is_anticipated boolean,
    dt_photographer_accepted timestamp,
    dt_job_created timestamp,
    dt_job_issued timestamp,
    dt_shoot_started timestamp,
    dt_job_scheduled timestamp,
    dt_photos_uploaded timestamp,
    dt_updated timestamp,
    dt_problem_reported timestamp,
    dt_photographer_start timestamp,
    user_cancel_dt timestamp,
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
  's3://dw.s3.data.quintoandar.com.br/public/dim_photo_job'
TBLPROPERTIES (
  'parquet.compress'='SNAPPY')
;