/******************************************************************************************************************
    The data migration from Asterisk to Teravoz and the integration with BigFone was completed in September 2019. 
    Because of this, we are filtering all call data from that date.
******************************************************************************************************************/
drop view if exists dw_teravoz_prod.dim_call;
create or replace view dw_teravoz_prod.dim_call as
with call_events as (
    select *
    from datalake_bigfone_clean_prod.events
    where date(concat(cast(year as varchar(4)), '-',
                      cast(month as varchar(2)), '-',
                      cast(day as varchar(2))))>= date('2019-09-01')
),
calls as (
    select distinct id_call from call_events
),
call_context_data as (
    select
        id_call,
        json_extract_scalar(metadata, '$.direction') as call_direction,
        json_extract_scalar(metadata, '$.our_number') as inside_phone_number,
        json_extract_scalar(metadata, '$.their_number') as outside_phone_number,
        json_extract_scalar(metadata, '$.their_number_type') as outside_phone_type
    from call_events
    where event='call.standby' 
          or event='call.new' 
          or event='call.waiting'
          or event='call.ongoing'
          or event='call.finished'
    group by 1,2,3,4,5
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
    context.outside_phone_type as external_phone_type,
    context.call_direction as direction,
    case 
        when context.call_direction='inbound' then  context.inside_phone_number
        when context.call_direction='outbound' then context.outside_phone_number
        when context.call_direction='internal' then context.outside_phone_number
    end as called_phone_number,
    case 
        when context.call_direction='inbound' then  context.outside_phone_number
        when context.call_direction='outbound' then context.inside_phone_number
        when context.call_direction='internal' then context.inside_phone_number
    end as caller_phone_number,
    context.outside_phone_number as external_phone_number,
    dial.phone as user_dialed_phone_number,
    r.recording_url as recording_url
from calls c
left join call_context_data context
on c.id_call=context.id_call
left join calls_recording r
on c.id_call=r.id_call
left join dialed_phone dial
on c.id_call=dial.id_call
;