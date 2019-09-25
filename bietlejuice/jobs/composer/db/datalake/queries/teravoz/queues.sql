select
    int(id) as id,
    smallint(number) as number,
    name,
    smallint(logged_in) as agents_logged,
    current_timestamp as ts_load,
    smallint(year) as year,
    tinyint(month) as month,
    tinyint(day) as day
from
    datalake_teravoz_raw.queues
where
    year="{year}" and month="{month}" and day="{day}"