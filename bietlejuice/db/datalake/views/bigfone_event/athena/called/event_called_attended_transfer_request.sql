drop view if exists datalake_bigfone_clean_prod.event_called_attended_transfer_request;
create or replace view datalake_bigfone_clean_prod.event_called_attended_transfer_request as
select
    id,
    id_call,
    json_extract_scalar(metadata, '$.direction') as call_direction,
    json_extract_scalar(metadata, '$.to') as destination_called_number,
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
    event='called.attended-transfer-request';