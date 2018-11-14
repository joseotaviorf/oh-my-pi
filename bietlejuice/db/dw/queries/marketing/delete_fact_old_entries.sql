delete from marketing.{table_name}
where {sk_field} in (
    select {sk_field}
    from staging.{table_name}
    where sk_date = '__PARTITION_DATE__'
) and sk_date = '__PARTITION_DATE__'