select
    id_call,
    cast(sum(if(get_json_object(metadata, '$.Resposta')='0',0, 1)) as boolean) as is_csat_set,
    max(case
        when get_json_object(metadata, '$.CSat1')='1' then true
        when get_json_object(metadata, '$.CSat1')='2' then false
    end) as has_call_satisfied_customer,
    max(cast(get_json_object(metadata, '$.CSat2') as tinyint)) as csat_rating,
    min(ts_created) as ts_started,
    min(ts_created_local) as ts_started_local,
    max(ts_created) as ts_ended,
    max(ts_created_local) as ts_ended_local,
    (cast(max(ts_created) as bigint) - cast(min(ts_created) as bigint)) as seconds_csat_duration,
    date(concat(cast(year as varchar(4)), '-', cast(month as varchar(2)), '-', cast(day as varchar(2)))) as dt_event,
    year,
    month,
    day
from     
    datalake_bigfone_clean.events
where
    event='call.data-provided'
    and (get_json_object(metadata, '$.CSat1') is not null or
         get_json_object(metadata, '$.CSat2') is not null or
         get_json_object(metadata, '$.Resposta') is not null)
    and year={year} and month={month} and day={day}
group by 1, 10, 11, 12, 13