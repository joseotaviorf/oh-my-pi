/******************************************************************************************************************
    The data migration from Asterisk to Teravoz and the integration with BigFone was completed in September 2019. 
    Because of this, we are filtering all call data from that date.
******************************************************************************************************************/
drop view if exists dw_teravoz_prod.dim_call;
create or replace view dw_teravoz_prod.dim_call as
with call_events as (
    select * 
    from datalake_bigfone_clean_prod.events 
    where date_format(ts_created, '%Y-%m-%d') >= '2019-09-01'
),
calls as (
    select distinct id_call from call_events group by 1
),
call_new_events as (
    select * from datalake_bigfone_clean_prod.call_new_events
    where dt_event >= date('2019-09-01')
),
-- Bigfone can receive the same event multiple times, but it assigns different ids
-- just observed in call new events
call_new_duplicated as (
    select id_call, min(id) as id from call_new_events group by 1
),
call_new as (
    select e.* from call_new_events e
    inner join call_new_duplicated d
    on e.id_call=d.id_call and e.id=d.id
),
calls_recording as (
    select 
        id_call, 
        recording_url
    from datalake_bigfone_clean_prod.call_recording_available_events
    where dt_event >= date('2019-09-01')
    group by 1,2
),
-- gets the user dialed phone (open column values for typing)
dialed_phone as (
    select 
        id_call, 
        json_extract_scalar(metadata, '$.data') as phone
    from call_events
    where 
        event='call.data-provided'
        and json_extract_scalar(metadata, '$.tag')='dialed_phone'
        and length(json_extract_scalar(metadata, '$.data'))>=8  -- valid phone size
    group by 1,2
)
select
    c.id_call as sk_call,
    new.outside_phone_type as external_phone_type,
    new.call_direction as direction,
    case 
        when new.call_direction='inbound' then  new.outside_phone_number
        when new.call_direction='outbound' then new.inside_phone_number
        when new.call_direction='internal' then new.outside_phone_number
    end as called_phone_number,
    new.caller_phone_number as caller_phone_number,
    new.outside_phone_number as external_phone_number,
    dial.phone as user_dialed_phone_number,
    r.recording_url as recording_url
from calls c
left join call_new new
on c.id_call=new.id_call
left join calls_recording r
on c.id_call=r.id_call
left join dialed_phone dial
on c.id_call=dial.id_call
;