select 
    int(queue) as queue_number,
    int(days.abandonedCalls) as calls_abandoned,
    int(days.answeredCalls) as calls_answered,
    int(days.receivedCalls) as calls_received,
    int(days.timedOutCalls) as calls_timed_out,
    date(days.callDate) as dt_created,
    current_timestamp as ts_load,
    smallint(year) as year,
    tinyint(month) as month,
    tinyint(day) as day
from
    (select queue, year, month, day, explode(days) as days from datalake_teravoz_raw.report_queue_stats
    where year={year} and month={month} and day={day})