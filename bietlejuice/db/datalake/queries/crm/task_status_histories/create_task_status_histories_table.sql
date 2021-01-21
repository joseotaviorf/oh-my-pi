with json_entries as (
    select
        json_parse(task_status_histories_entry) as task_status_histories_entry,
        dt
    from datalake_raw.crm_task_status_histories
    where dt = '__PARTITION_DATE__'
)
select
    cast(json_extract(task_status_histories_entry, '$._id') as varchar) as id,
    cast(json_extract(task_status_histories_entry, '$.__v') as varchar) as v,
    json_format(json_extract(task_status_histories_entry, '$.history')) as histories
from json_entries
;