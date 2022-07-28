drop view if exists datalake_bigfone_clean_prod.service_command_events;
create or replace view datalake_bigfone_clean_prod.service_command_events as
select
    id,
    id_call,
    cast(json_extract_scalar(metadata, '$.from') as integer) as extension_number,
    json_extract_scalar(metadata, '$.command') as internal_command,
    ts_created,
    ts_created_local,
    ts_received,
    ts_received_local,
    date(concat(cast(year as varchar(4)), '-', cast(month as varchar(2)), '-', cast(day as varchar(2)))) as dt_event
from     
    datalake_bigfone_clean_prod.events
where 
    event='service.command';