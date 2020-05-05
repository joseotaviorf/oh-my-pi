select
    min(id) as id,
    id_call,
    ts_created,
    ts_created_local,
    ts_received,
    ts_received_local,
    date(concat(cast(year as varchar(4)), '-', cast(month as varchar(2)), '-', cast(day as varchar(2)))) as dt_event,
    year,
    month,
    day
from
    datalake_bigfone_clean.events
where
    (event='actor.entered'
    or event='call.finished'
    or event='call.queue-abandon')
    and year={year} and month={month} and day={day}
group by 2,3,4,5,6,7,8,9,10