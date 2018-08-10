delete from staging.{table_name}
where dt_partition = '{partition_date}'
;