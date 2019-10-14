select
    bigint(id) as id,
    event,
    get_json_object(metadata, '$.call_id') as id_call,
    metadata,
    date_format(event_timestamp, 'y-MM-dd hh:mm:ss') as ts_created,
    date_format(from_utc_timestamp(event_timestamp, 'America/Sao_Paulo'), 'y-MM-dd hh:mm:ss') as ts_created_local,
    date_format(received_timestamp, 'y-MM-dd hh:mm:ss') as ts_received,
    date_format(from_utc_timestamp(received_timestamp, 'America/Sao_Paulo'), 'y-MM-dd hh:mm:ss') as ts_received_local,
    year,
    month,
    day
from     
    datalake_bigfone_raw.events
where 
    year={year} and month={month} and day={day}
    and provider='teravoz'