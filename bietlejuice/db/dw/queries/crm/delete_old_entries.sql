delete from crm.{table_name}
where sk_task in (
    select sk_task
    from staging.{table_name}
    where dt_partition = '{partition_date}'
)
;