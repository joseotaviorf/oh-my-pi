drop view if exists datalake_bigfone_clean_prod.called_attended_transfer_request_events;
create or replace view datalake_bigfone_clean_prod.called_attended_transfer_request_events as
select
    id,
    id_call,
    json_extract_scalar(metadata, '$.direction') as call_direction,
    json_extract_scalar(metadata, '$.to') as destination_called_number,
    ts_created,
    ts_created_local,
    ts_received,
    ts_received_local,
    date(concat(cast(year as varchar(4)), '-', cast(month as varchar(2)), '-', cast(day as varchar(2)))) as dt_event
from
    datalake_bigfone_clean_prod.events
where
    event='called.attended-transfer-request';