delete from {table_name}
where id in (
    select id
    from stg.{table_name}
    group by 1
)
;