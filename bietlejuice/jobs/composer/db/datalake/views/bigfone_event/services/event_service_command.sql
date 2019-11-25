drop view if exists datalake_bigfone_clean_prod.event_service_command;
create or replace view datalake_bigfone_clean_prod.event_service_command as
select
    id,
    id_call,
    cast(json_extract_scalar(metadata, '$.from') as integer) as extension_number,
    json_extract_scalar(metadata, '$.command') as internal_command,
    ts_created,
    ts_created_local,
    ts_received,
    ts_received_local,
    year,
    month,
    day
from     
    datalake_bigfone_clean_prod.events
where 
    event='service.command';