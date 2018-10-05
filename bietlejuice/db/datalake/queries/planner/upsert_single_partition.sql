alter table {schema}.planner_{enum_value}
  add if not exists partition (dt='{dt_partition}', {enum_value}='{id_class}')
  location 's3://{s3_bucket}/{bucket_type}/planner/dt={dt_partition}/{enum_value}={id_class}'
;