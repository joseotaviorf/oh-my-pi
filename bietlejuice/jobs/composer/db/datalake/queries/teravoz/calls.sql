select
    call_id as id, --format xxxx-xxxxxxxx.xxxxxxxx
    timestamp(call_date) as ts_started_local,
    to_utc_timestamp(call_date, 'America/Sao_Paulo') as ts_started,
    called_number as called_phone_number,
    caller_number as caller_phone_number,
    extension as internal_phone_number,
    number_type as caller_phone_type, 
    round(float(price), 2) as price,
    source as source_phone_number,
    smallint(talk_time) as seconds_talk_duration,
    status,
    type as call_direction,
    current_timestamp as ts_load,
    smallint(year) as year,
    tinyint(month) as month,
    tinyint(day) as day
from
    datalake_teravoz_raw.calls
where
    year="{year}" and month="{month}" and day="{day}"