drop view if exists datalake_bigfone_clean_prod.call_recording_available_events;
create or replace view datalake_bigfone_clean_prod.call_recording_available_events as
select
    id,
    id_call,
    json_extract_scalar(metadata, '$.url') as recording_url,
    ts_created,
    ts_created_local,
    ts_received,
    ts_received_local,
    date(concat(cast(year as varchar(4)), '-', cast(month as varchar(2)), '-', cast(day as varchar(2)))) as dt_event
from     
    datalake_bigfone_clean_prod.events
where
    event='call.recording-available';