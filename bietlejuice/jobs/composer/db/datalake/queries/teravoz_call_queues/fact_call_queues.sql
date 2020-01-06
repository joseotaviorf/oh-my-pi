/******************************************************************************************************************
    The data migration from Asterisk to Teravoz and the integration with BigFone was completed in September 2019. 
    Because of that, we are filtering all call data from that date.
******************************************************************************************************************/
with 
    queues as (
        select * 
        from datalake_teravoz_clean.queues
        where year={year} and month={month} and day={day}
              and date(concat(string(year), '-', 
                              string(month), '-', 
                              string(day)))>= date('2019-09-01')
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
        on q.number=ql.number 
           and q.ts_load=ql.max_ts_load
        group by 1,2
    ),
    call_events as (
        select *
        from datalake_bigfone_clean.events
        where year={year} and month={month} and day={day}
              and date(concat(string(year), '-', 
                              string(month), '-', 
                              string(day)))>= date('2019-09-01')
    ),
    calls as (
        select distinct id_call from call_events
    ),
    waiting_events as (
        select
            id,
            id_call,
            cast(get_json_object(metadata, '$.queue') as smallint) as queue_number,
            ts_created,
            ts_created_local
        from call_events
        where event='call.waiting'
    ),
    waiting_next_events as (
        select
            id,
            id_call,
            ts_created,
            ts_created_local
        from call_events
        where event='actor.ringing' or event='call.finished'
        group by 1,2,3,4
    ),
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
        inner join waiting_next_events wait_next
        on wait.id_call = wait_next.id_call
           and wait.ts_created <= wait_next.ts_created
        group by 1,2,3,4,5
    ),
    blind_transfer as (
        select
            id_call,
            cast(get_json_object(metadata, '$.to') as smallint) as queue_number,
            ts_created,
            ts_created_local
        from call_events
        where event='called.blind-transfer'
    ),
    abandoned_queue as (
        select
            id_call,
            cast(get_json_object(metadata, '$.queue') as smallint) as queue_number,
            ts_created,
            ts_created_local
        from call_events
        where event='call.queue-abandon'
    ),
    call_finished as (
        select
            id,
            id_call,
            ts_created,
            ts_created_local
        from call_events
        where event='call.finished'
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
            coalesce(mp.id, sp.id, bp.id, op.id) as id_user,
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
        group by 1,2
    ),
    dialed_user_phone as (
        select
            coalesce(mp.id, sp.id, bp.id, op.id) as id_user,
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
        group by 1,2
    )
select
    wti.id as sk_call_queued,
    c.id_call as sk_call,
    wti.queue_number as sk_queue,
    coalesce(outside.id_user, dial.id_user) as sk_user,
    int(date_format(wti.ts_created_wait_event, 'yyyyMMdd')) as sk_call_date,
    int(date_format(wti.ts_created_wait_event_local, 'yyyyMMdd')) as sk_call_date_local,
    wti.queue_number,
    qn.name as queue_name,
    to_unix_timestamp(wti.ts_created_next_wait_event, 'yyyy-MM-dd HH:mm:ss') - 
        to_unix_timestamp(wti.ts_created_wait_event, 'yyyy-MM-dd HH:mm:ss') as seconds_queue_waiting_duration,
    (wtit.id is not null) as is_same_queue_transferred,
    (bt.queue_number is not null) as is_blind_transfer,
    (aq.id_call is not null) as is_call_abandoned_in_queue,
    wti.ts_created_wait_event as ts_queue_joined,
    wti.ts_created_wait_event_local as ts_queue_joined_local,
    bt.ts_created as ts_blinded_transfer,
    bt.ts_created_local as ts_blinded_transfer_local,
    coalesce(aq.ts_created, cf.ts_created) as ts_call_abandoned_in_queue,
    coalesce(aq.ts_created_local, cf.ts_created_local) as ts_call_abandoned_in_queue_local,
    wti.ts_created_next_wait_event as ts_queue_left,
    wti.ts_created_next_wait_event_local as ts_queue_left_local
from calls c
inner join wait_time_interactions wti 
    on c.id_call=wti.id_call
left join outside_user_phone outside
    on c.id_call=outside.id_call
left join dialed_user_phone dial
    on c.id_call=dial.id_call
inner join queues_name qn 
    on wti.queue_number = qn.number
left join wait_time_interactions wtit 
    on wti.id <> wtit.id 
       and wti.id_call = wtit.id_call 
       and wti.queue_number = wtit.queue_number 
       and wti.ts_created_wait_event > wtit.ts_created_wait_event
left join blind_transfer bt 
    on wti.id_call = bt.id_call 
       and wti.queue_number = bt.queue_number 
       and bt.ts_created <= wti.ts_created_wait_event
left join abandoned_queue aq 
    on wti.id_call = aq.id_call 
       and wti.queue_number = cast(aq.queue_number as smallint)
left join call_finished cf 
    on wti.id_call = cf.id_call 
       and wti.next_event_id = cf.id