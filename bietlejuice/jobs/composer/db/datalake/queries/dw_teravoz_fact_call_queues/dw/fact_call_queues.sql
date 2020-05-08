with 
    queues as (
        select * from datalake_teravoz_clean.queues
        where date(concat(cast(year as varchar(4)), '-',
                          cast(month as varchar(2)), '-',
                          cast(day as varchar(2))))>= date('2019-09-01')
    ),
    -- the queues are replicated daily, so the last load contains the more recent data. 
    queues_last_update as (
        select number, max(ts_load) as max_ts_load
        from queues
        group by 1
    ),
    queues_name as (
        select
            q.number,
            q.name
        from queues q
        inner join queues_last_update ql
        on q.number=ql.number and q.ts_load=ql.max_ts_load
        group by 1,2
    ),
    call_events as (
        select *
        from datalake_bigfone_clean.events
        where date(concat(cast(year as varchar(4)), '-',
                    cast(month as varchar(2)), '-',
                    cast(day as varchar(2)))) >= date('2019-09-01')
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
    waiting_next_events as (
        select
            min(id) as id,
            id_call,
            ts_created,
            ts_created_local
        from datalake_bigfone.call_waiting_next_events
        where dt_event >= date('2019-09-01')
        group by 2,3,4
    ),
    /*
        wait_time_interactions = time diff between the next riging, queue-abandon or finished event immediately after 'call_waiting' event and 'call_waiting' event
        A call can have multiple call_waiting event. So we find the pair (call_waiting, next_event) when:
        1. the events compared are different  
        2. min(ts_next_event) >= ts_call_waiting, and ts_call_ringing is the closest to ts_call_waiting
        3. id_call is the same
    */
    wait_time_interactions as (
        select
            wait.id,
            wait.id_call,
            wait.queue_number,
            wait.ts_created as ts_created_wait_event,
            wait.ts_created_local as ts_created_wait_event_local,
            min(wait_next.id) as next_event_id,
            min(wait_next.ts_created) as ts_created_next_wait_event,
            min(wait_next.ts_created_local) as ts_created_next_wait_event_local
        from waiting_events wait
        left join waiting_next_events wait_next
        on wait.id_call = wait_next.id_call
        and wait.ts_created <= wait_next.ts_created
        group by 1,2,3,4,5
    ),
    /* 
        same_queue_transferred = it must find out if the queue has been transferred to the same queue number:
        So we must find the previous waiting event (queue event) to queue event we are analyzing: 
        1. In the first waiting event has no queue transfer in call yet.  
        2. min(ts_waiting_event) > ts_previous_waiting_event
        3. queue_number must be the same.
    */
    same_queue_transferred as (
        select distinct prev.id
        from wait_time_interactions prev
        inner join wait_time_interactions next
        on prev.id<>next.id
        and prev.ts_created_wait_event > next.ts_created_wait_event
        and prev.queue_number=next.queue_number
        and prev.id_call=next.id_call
    ),
    /* blind_transfer is a event that occurres before waiting event. 
        The metric logic is the same as wait_time_interactions, just inverted min to max.
    */  
    blind_transfer as (
        select
            wti.id,
            max(bt.ts_created) as ts_created,
            max(bt.ts_created_local) as ts_created_local
        from datalake_bigfone.called_blind_transfer_events bt
        inner join wait_time_interactions wti 
        on wti.id_call = bt.id_call 
        and wti.queue_number = destination_called_number
        and bt.ts_created <= wti.ts_created_wait_event
        where dt_event >= date('2019-09-01')
        group by 1
    ),
    abandoned_queue as (
        select
            id_call,
            queue_number,
            ts_created,
            ts_created_local
        from datalake_bigfone.call_queue_abandon_events
        where dt_event >= date('2019-09-01')
        group by 1,2,3,4
    ),
    call_finished as (
        select
            min(id) as id,
            id_call,
            ts_created,
            ts_created_local
        from datalake_bigfone.call_finished_events
        where dt_event >= date('2019-09-01')
        group by 2,3,4
    ),
    outside_user_phone as (
        select
            id_user,
            id_call
        from datalake_user_phone.incoming_user_phone
        where date(concat(cast(year as varchar(4)), '-',
                      cast(month as varchar(2)), '-',
                      cast(day as varchar(2)))) >= date('2019-09-01')
        group by 1,2
    ),
    dialed_user_phone as (
        select
            id_user,
            id_call
        from datalake_user_phone.dialed_user_phone
        where date(concat(cast(year as varchar(4)), '-',
                      cast(month as varchar(2)), '-',
                      cast(day as varchar(2)))) >= date('2019-09-01')
        group by 1,2
    )
select
    wti.id as sk_call_queued,
    c.id_call as sk_call,
    wti.queue_number as sk_queue,
    coalesce(outside.id_user, dial.id_user) as sk_user,
    cast(date_format(wti.ts_created_wait_event, "yyyyMMdd") as bigint) as sk_call_date,
    cast(date_format(wti.ts_created_wait_event_local, "yyyyMMdd") as bigint) as sk_call_date_local,
    wti.queue_number,
    qn.name as queue_name,
    unix_timestamp(wti.ts_created_next_wait_event) - unix_timestamp(wti.ts_created_wait_event) as seconds_queue_waiting_duration,
    (transf.id is not null) as is_same_queue_transferred,
    (bt.id is not null) as is_blind_transfer,
    (aq.id_call is not null) as is_call_abandoned_in_queue,
    wti.ts_created_wait_event as ts_queue_joined,
    wti.ts_created_wait_event_local as ts_queue_joined_local,
    bt.ts_created as ts_blinded_transfer,
    bt.ts_created_local as ts_blinded_transfer_local,
    coalesce(aq.ts_created, cf.ts_created) as ts_call_abandoned_in_queue,
    coalesce(aq.ts_created_local, cf.ts_created_local) as ts_call_abandoned_in_queue_local,
    wti.ts_created_next_wait_event as ts_queue_left,
    wti.ts_created_next_wait_event_local as ts_queue_left_local,
    now() as ts_load
from calls c
inner join wait_time_interactions wti 
on c.id_call=wti.id_call
left join outside_user_phone outside
on c.id_call=outside.id_call
left join dialed_user_phone dial
on c.id_call=dial.id_call
inner join queues_name qn 
on wti.queue_number = qn.number
left join same_queue_transferred transf 
on wti.id=transf.id
left join blind_transfer bt 
on wti.id = bt.id
left join abandoned_queue aq 
on wti.id_call = aq.id_call 
and wti.queue_number = aq.queue_number
left join call_finished cf 
on wti.id_call = cf.id_call 
and wti.next_event_id = cf.id
