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
        from call_events
        where 
            event='actor.entered' 
            or event='call.finished' 
            or event='call.queue-abandon'
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
        group by 2,3,4
    ),
    outside_phone as (
        select
            id_call, 
            get_json_object(metadata, '$.their_number') as outside_phone
        from call_events
        where event='call.new'
        group by 1,2
    ),
    -- gets the user dialed phone (open column values for typing)
    dialed_phone as (
      select 
          id_call, 
          get_json_object(metadata, '$.data') as dialed_phone
      from call_events
      where 
          event='call.data-provided'
          and get_json_object(metadata, '$.tag')='dialed_phone'
          and length(get_json_object(metadata, '$.data'))>=8  -- valid phone size
      group by 1,2
    ),
    -- the max(id) was used to users table from EBDB because a user can have the same phone in the same column. 
    -- returns the most recent user
    -- the phones received by the Teravoz don't have the prefix +55.
    ebdb_main_phone as (
        select 
            max(id) as id,
            replace(main_phone,'+55') as main_phone
        from datalake_ebdb_clean.user
        where main_phone is not null
        group by 2
    ),
    ebdb_secondary_phone as (
        select 
            max(id) as id,
            replace(secondary_phone,'+55') as secondary_phone
        from datalake_ebdb_clean.user
        where secondary_phone is not null
        group by 2
    ),
    ebdb_business_phone as (
        select 
            max(id) as id,
            replace(business_phone,'+55') as business_phone
        from datalake_ebdb_clean.user
        where business_phone is not null
        group by 2
    ),
    ebdb_old_phone as (
        select 
            max(id) as id,
            replace(old_phone,'+55') as old_phone
        from datalake_ebdb_clean.user
        where old_phone is not null
        group by 2
    ),
    outside_user_phone as (
        select
            max(coalesce(mp.id, sp.id, bp.id, op.id)) as id_user,
            outside.id_call
        from outside_phone outside
        left join ebdb_main_phone mp
        on outside.outside_phone=mp.main_phone
        left join ebdb_secondary_phone sp
        on outside.outside_phone=sp.secondary_phone
        left join ebdb_business_phone bp
        on outside.outside_phone=bp.business_phone
        left join ebdb_old_phone op
        on outside.outside_phone=op.old_phone
        where coalesce(mp.id, sp.id, bp.id, op.id) is not null
        group by 2
    ),
    dialed_user_phone as (
        select
            max(coalesce(mp.id, sp.id, bp.id, op.id)) as id_user,
            dial.id_call
        from dialed_phone dial
        left join ebdb_main_phone mp
        on dial.dialed_phone=mp.main_phone
        left join ebdb_secondary_phone sp
        on dial.dialed_phone=sp.secondary_phone
        left join ebdb_business_phone bp
        on dial.dialed_phone=bp.business_phone
        left join ebdb_old_phone op
        on dial.dialed_phone=op.old_phone
        where coalesce(mp.id, sp.id, bp.id, op.id) is not null
        group by 2
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