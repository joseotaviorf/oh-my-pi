delete from marketing.{table_name}
where sk_keyword in (
    select sk_keyword
    from staging.{table_name}
    where dt_created = '__PARTITION_DATE__'
) and dt_created = '__PARTITION_DATE__'