drop view if exists datalake_bigfone_clean_prod.agent_left_events;
create or replace view datalake_bigfone_clean_prod.agent_left_events as
select
    id,
    id_call,
    json_extract_scalar(metadata, '$.actor') as agent_email,
    cast(json_extract_scalar(metadata, '$.queue') as smallint) as queue_number,
    cast(json_extract_scalar(metadata, '$.number') as integer) as extension_number,
    ts_created,
    ts_created_local,
    ts_received,
    ts_received_local,
    date(concat(cast(year as varchar(4)), '-', cast(month as varchar(2)), '-', cast(day as varchar(2)))) as dt_event
from     
    datalake_bigfone_clean_prod.events
where 
    event='actor.left';