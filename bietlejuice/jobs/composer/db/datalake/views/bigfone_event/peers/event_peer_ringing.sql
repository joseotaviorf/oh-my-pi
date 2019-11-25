drop view if exists datalake_bigfone_clean_prod.event_peer_ringing;
create or replace view datalake_bigfone_clean_prod.event_peer_ringing as
select
    id,
    id_call,
    cast(json_extract_scalar(metadata, '$.number') as integer) as extension_number,
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
    event='peer.ringing';