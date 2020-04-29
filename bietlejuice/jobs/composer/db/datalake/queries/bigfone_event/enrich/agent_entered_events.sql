select
    id,
    id_call,
    get_json_object(metadata, '$.actor') as agent_email,
    cast(get_json_object(metadata, '$.queue') as smallint) as queue_number,
    cast(get_json_object(metadata, '$.number') as integer) as extension_number,
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
    event='actor.entered'
    and year={year} and month={month} and day={day}