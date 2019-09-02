select 
    smallint(queue) as queue_number,
    date(callDate) as dt_created,
    smallint(abandonedCalls) as calls_abandoned,
    smallint(answeredCalls) as calls_answered,
    smallint(receivedCalls) as calls_received,
    smallint(timedOutCalls) as calls_timed_out,
    current_timestamp as ts_load,
    year,
    month,
    day
from
    (select queue, year, month, day, inline(days) from datalake_teravoz_raw.report_queue_stats
    where year="{year}" and month="{month}" and day="{day}")