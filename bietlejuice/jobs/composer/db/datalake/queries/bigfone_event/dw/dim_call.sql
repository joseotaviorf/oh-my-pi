/******************************************************************************************************************
    The data migration from Asterisk to Teravoz and the integration with BigFone was completed in September 2019. 
    Because of this, we are filtering all call data from that date.
******************************************************************************************************************/
with
    call_events as (
        select *
        from datalake_bigfone_clean.events
        where date(concat(cast(year as varchar(4)), '-',
                      cast(month as varchar(2)), '-',
                      cast(day as varchar(2))))>= date('2019-09-01')
    ),
    calls as (
        select distinct id_call
        from call_events
    ),
    call_context_data as (
        select
            id_call,
            call_direction,
            quinto_andar_number,
            incoming_phone_number,
            incoming_phone_type
        from datalake_bigfone.call_context_data
        group by 1,2,3,4,5
    ),
    calls_recording as (
        select
            id_call,
            recording_url
        from datalake_bigfone.call_recording_available_events
        where dt_event >= date('2019-09-01')
        group by 1,2
    ),
    -- gets the user dialed phone (open column values for typing)
    dialed_phone as (
        select
            id_call,
            phone
        from datalake_bigfone.dialed_phone
        group by 1,2
    )
select
    c.id_call as sk_call,
    ccd.incoming_phone_type as external_phone_type,
    ccd.call_direction as direction,
    case
        when ccd.call_direction='inbound' then  ccd.quinto_andar_number
        when ccd.call_direction='outbound' then ccd.incoming_phone_number
        when ccd.call_direction='internal' then ccd.incoming_phone_number
    end as called_phone_number,
    case
        when ccd.call_direction='inbound' then  ccd.incoming_phone_number
        when ccd.call_direction='outbound' then ccd.quinto_andar_number
        when ccd.call_direction='internal' then ccd.quinto_andar_number
    end as caller_phone_number,
    ccd.incoming_phone_number as external_phone_number,
    dp.phone as user_dialed_phone_number,
    cr.recording_url as recording_url,
    now() as ts_load
from calls c
    left join call_context_data ccd
    on c.id_call=ccd.id_call
    left join calls_recording cr
    on c.id_call=cr.id_call
    left join dialed_phone dp
    on c.id_call=dp.id_call