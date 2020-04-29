select
    id,
    id_call,
    cast(get_json_object(metadata, '$.queue') as smallint) as  queue_number,
    get_json_object(metadata, '$.direction') as call_direction,
    get_json_object(metadata, '$.our_number') as quinto_andar_number,
    get_json_object(metadata, '$.their_number') as incoming_phone_number,
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
    event='call.waiting'
    and year={year} and month={month} and day={day}