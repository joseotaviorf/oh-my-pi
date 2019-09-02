  select
    int(id) as id,
    smallint(number) as queue_number,
    description,
    smallint(logged_in) as agents_logged,
    current_timestamp as ts_load
from
    datalake_teravoz_raw.queues
where
    year="{year}" and month="{month}" and day="{day}"