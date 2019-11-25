drop view if exists datalake_bigfone_clean_prod.call_queue_abandon_events;
create or replace view datalake_bigfone_clean_prod.call_queue_abandon_events as
select
    id,
    id_call,
    cast(json_extract_scalar(metadata, '$.queue') as smallint) as queue_number,
    ts_created,
    ts_created_local,
    ts_received,
    ts_received_local,
    date(concat(cast(year as varchar(4)), '-', cast(month as varchar(2)), '-', cast(day as varchar(2)))) as dt_event
from     
    datalake_bigfone_clean_prod.events
where 
    event='call.queue-abandon';