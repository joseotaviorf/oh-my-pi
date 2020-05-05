select
    id,
    id_call,
    get_json_object(metadata, '$.direction') as call_direction,
    get_json_object(metadata, '$.our_number') as quinto_andar_number,
    get_json_object(metadata, '$.their_number') as incoming_phone_number,
    get_json_object(metadata, '$.their_number_type') as incoming_phone_type,
    date(concat(cast(year as varchar(4)), '-', cast(month as varchar(2)), '-', cast(day as varchar(2)))) as dt_event,
    ts_created,
    ts_created_local,
    ts_received,
    ts_received_local,
    year,
    month,
    day
from
    datalake_bigfone_clean.events
where
    (event='call.standby'
    or event='call.new'
    or event='call.waiting'
    or event='call.ongoing'
    or event='call.finished')
    and year={year} and month={month} and day={day}
group by 1,2,3,4,5,6,7,8,9,10,11,12,13,14