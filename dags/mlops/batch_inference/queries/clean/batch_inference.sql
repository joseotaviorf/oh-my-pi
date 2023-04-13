select
  model_name,
  model_version,
  input_data,
  output_data,
  metadata,
  timestamp(timestamp) as ts_inference,
  year,
  month,
  day
from
  datalake_batch_inference_raw.batch_inference
where year={year} AND month={month} AND day={day}
