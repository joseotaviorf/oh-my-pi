select
    id,
    id_call,
    get_json_object(metadata, '$.url') as recording_url,
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
    event='call.recording-available'
    and year={year} and month={month} and day={day}