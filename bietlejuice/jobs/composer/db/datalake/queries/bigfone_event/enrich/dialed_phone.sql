select
    id,
    id_call,
    get_json_object(metadata, '$.data') as phone,
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
    event='call.data-provided'
    and get_json_object(metadata, '$.tag') = 'dialed_phone'
    and length(get_json_object(metadata, '$.data')) >= 8  -- valid phone size
    and year={year} and month={month} and day={day}
group by 1,2,3,4,5,6,7,8,9,10,11