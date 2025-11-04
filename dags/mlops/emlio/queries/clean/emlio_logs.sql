select 
  uuid,
  service_id as id_service,
  service_version,
  inference_type,
  service_type,
  timestamp(log_timestamp) as ts_log,
  inputs,
  outputs,
  keys as service_keys,
  deployment_info,
  year,
  month,
  day
from 
  datalake_emlio_raw.emlio_logs
where year={year} AND month={month} AND day={day}