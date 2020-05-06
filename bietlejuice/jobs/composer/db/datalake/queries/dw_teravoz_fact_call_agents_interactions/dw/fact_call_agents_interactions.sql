with call_events as (
    select *
    from datalake_bigfone_clean.events
    where date(concat(cast(year as varchar(4)), '-',
                      cast(month as varchar(2)), '-',
                      cast(day as varchar(2))))>= date('2019-09-01')
),
calls as (
    select distinct id_call from call_events
),
waiting_events as (
    select
        min(id) as id,
        id_call,
        queue_number,
        ts_created,
        ts_created_local
    from datalake_bigfone.call_waiting_events
    where dt_event >= date('2019-09-01')
    group by 2,3,4,5
),
ringing_events as (
    select
        id_call,
        agent_email,
        ts_created
    from datalake_bigfone.agent_ringing_events
    where dt_event >= date('2019-09-01')
    group by 1,2,3
),
agents_in_call as (
    select
        c.id_call,
        ring.agent_email,
        max(wait.id) as id_call_queued
    from calls c
    inner join waiting_events wait
    on c.id_call = wait.id_call
    inner join ringing_events ring
    on c.id_call = ring.id_call
    and wait.ts_created <= ring.ts_created
    group by 1,2
),
agent as (
    select
        id,
        ac.id_call,
        u.email,
        (u.id is null) as outsourcing_company
    from agents_in_call ac
    left join datalake_ebdb_clean.user u
    on ac.agent_email = u.email
),
agent_entered_events as (
	select 
        min(id) as id,
        id_call,
        agent_email,
        extension_number,
        ts_created,
        ts_created_local
	from datalake_bigfone.agent_entered_events
	where dt_event >= date('2019-09-01')
    group by 2,3,4,5,6
),
agent_left_events as (
    select
        id_call,
        agent_email,
        ts_created,
        ts_created_local
    from datalake_bigfone.agent_left_events
    where dt_event >= date('2019-09-01')
    group by 1,2,3,4
),
talk_time as (
    select
        enter.id_call,
        enter.ts_created as ts_created_entered_event,
        enter.ts_created_local as ts_created_entered_event_local,
        enter.agent_email,
        enter.extension_number,
        min(lef.ts_created) as ts_created_left_event,
        min(lef.ts_created_local) as ts_created_left_event_local
    from agent_entered_events enter
    inner join agent_left_events lef
    on enter.id_call = lef.id_call
        and enter.agent_email = lef.agent_email
        and lef.ts_created >= enter.ts_created
    group by 1,2,3,4,5
),
call_ring_events as (
	select
        min(id) as id,
        id_call,
        agent_email,
        ts_created,
        ts_created_local
	from datalake_bigfone.agent_ringing_events
	where dt_event >= date('2019-09-01')
    group by 2,3,4,5
),
/******************************
 retrieve the first and last ring events for the call and consider the next event after the last as the stop
for the ring time
*******************************/
ring_summary as (
    select
        id_call,
        agent_email,
        ts_max,
        min(ts_min) as ts_min,
        min(ts_min_local) as ts_min_local
    from (
        select
            ring.id_call,
            ring.agent_email,
            ring.ts_created as ts_min,
            ring.ts_created_local as ts_min_local,
            min(ae.id) as enter_id,
            min(ae.ts_created) as ts_max
        from call_ring_events ring
        inner join agent_entered_events ae
        on ae.id_call = ring.id_call
            and ae.ts_created > ring.ts_created
        group by 1,2,3,4
    )
    group by 1,2,3
),
ring_events_into_summary as (
    select
        ring.id_call,
        ring.agent_email as agent_email,
        ring_summary.ts_min as ts_created_ring_event,
        ring_summary.ts_min_local as ts_created_ring_event_local,
        max(ring.ts_created) as ts_created_last_ring_event,
        max(ring.id) as last_ring_event_id
    from call_ring_events ring
    inner join ring_summary
    on ring_summary.id_call = ring.id_call
        and ring_summary.agent_email = ring.agent_email
        and ring.ts_created >= ring_summary.ts_min
        and ring.ts_created < ring_summary.ts_max
    group by 1,2,3,4
),
ring_time as (
    select
        ring.id_call,
        ring.ts_created_ring_event,
        ring.ts_created_ring_event_local,
        ring.agent_email,
        min(e.ts_created) as ts_created_next_ring_event
    from call_events e
    inner join ring_events_into_summary ring
    on ring.id_call = e.id_call
    and ring.ts_created_last_ring_event <= e.ts_created
    and e.id <> ring.last_ring_event_id
    group by 1,2,3,4
),
ring_talk_interaction as (
    select
        ring.id_call,
        ring.agent_email,
        ring.ts_created_ring_event,
        ring.ts_created_ring_event_local,
        ring.ts_created_next_ring_event,
        min(talk.ts_created_entered_event) as ts_created_talk_event,
        min(talk.ts_created_entered_event_local) as ts_created_talk_event_local
    from ring_time ring
    left join talk_time as talk
    on ring.id_call = talk.id_call
    and ring.agent_email = talk.agent_email
    and talk.ts_created_entered_event >= ring.ts_created_ring_event
    group by 1,2,3,4,5
)
select
   	re.id as sk_call_agent_interaction,
    c.id_call as sk_call,
    ac.agent_email as sk_agent,
    ac.id_call_queued as sk_call_queued,
    coalesce (a.id, -1) as sk_user,
    cast(date_format(tt.ts_created_entered_event, 'yyyyMMdd') as bigint) as sk_agent_answered_date,
    cast(date_format(tt.ts_created_entered_event_local, 'yyyyMMdd') as bigint) as sk_agent_answered_date_local,
    coalesce(a.email, tt.agent_email) email_agent,
    tt.extension_number as extension_number, 
    UNIX_TIMESTAMP(rti.ts_created_next_ring_event) -  UNIX_TIMESTAMP(rti.ts_created_ring_event) as seconds_call_ringing_time,
    UNIX_TIMESTAMP(tt.ts_created_left_event) -  UNIX_TIMESTAMP(tt.ts_created_entered_event) as seconds_talk_time_agent,
    (tt.id_call is not null) as is_call_answered_by_agent,
    a.outsourcing_company as is_call_answered_from_outsourcing_company,
    tt.ts_created_entered_event as ts_agent_answered,
    tt.ts_created_entered_event_local as ts_agent_answered_local,
    tt.ts_created_left_event as ts_agent_hangup,
    tt.ts_created_left_event_local as ts_agent_hangup_local,
    rti.ts_created_ring_event as ts_agent_extension_rang,
    rti.ts_created_ring_event_local as ts_agent_extension_rang_local,
    now() as ts_load
from calls c
inner join agents_in_call ac on c.id_call = ac.id_call
inner join agent a on c.id_call = a.id_call and ac.agent_email = a.email
inner join ring_talk_interaction rti on rti.id_call = c.id_call and rti.agent_email = ac.agent_email
inner join call_ring_events re on re.id_call = rti.id_call and re.agent_email = rti.agent_email and re.ts_created = rti.ts_created_ring_event
left join talk_time tt on rti.id_call = tt.id_call and rti.agent_email = tt.agent_email and tt.ts_created_entered_event = rti.ts_created_talk_event