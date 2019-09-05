select 
    int(queue) as queue_number,
    date(callDate) as dt_created,
    int(abandonedCalls) as calls_abandoned,
    int(answeredCalls) as calls_answered,
    int(receivedCalls) as calls_received,
    int(timedOutCalls) as calls_timed_out,
    current_timestamp as ts_load,
    smallint(year) as year,
    tinyint(month) as month,
    tinyint(day) as day
from
    (select queue, year, month, day, inline(days) from datalake_teravoz_raw.report_queue_stats
    where year="{year}" and month="{month}" and day="{day}")