drop view if exists datalake_bigfone_clean_prod.call_csat_events;
create or replace view datalake_bigfone_clean_prod.call_csat_events as
select
    id_call,
    if(json_extract_scalar(metadata, '$.Resposta')='0',false,true) as is_csat_set,
    max(case
        when json_extract_scalar(metadata, '$.CSat1')='1' then true
        when json_extract_scalar(metadata, '$.CSat1')='2' then false
    end) as is_call_satisfied_customer,
    max(cast(json_extract_scalar(metadata, '$.CSat2') as tinyint)) as csat_rating,
    min(ts_created) as ts_started,
    min(ts_created_local) as ts_started_local,
    max(ts_created) as ts_ended,
    max(ts_created_local) as ts_ended_local,
    date_diff('second', min(ts_created), max(ts_created)) as seconds_csat_duration,
    concat(cast(year as varchar(4)), '-', cast(month as varchar(2)), '-', cast(day as varchar(2))) as dt_event
from     
    datalake_bigfone_clean_prod.events
where
    event='call.data-provided'
    and (json_extract_scalar(metadata, '$.CSat1') is not null or 
         json_extract_scalar(metadata, '$.CSat2') is not null or
         json_extract_scalar(metadata, '$.Resposta') is not null)
group by 1, 2, 10;