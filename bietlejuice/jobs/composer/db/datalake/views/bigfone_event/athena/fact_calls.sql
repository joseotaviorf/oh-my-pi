/******************************************************************************************************************
    The data migration from Asterisk to Teravoz and the integration with BigFone was completed in September 2019. 
    Because of this, we are filtering all call data from that date.
******************************************************************************************************************/
drop view if exists dw_teravoz_prod.fact_calls;
create or replace view dw_teravoz_prod.fact_calls as
with 
    call_events as (
        select * 
        from datalake_bigfone_clean_prod.events 
        where date(concat(cast(year as varchar(4)), '-',
                          cast(month as varchar(2)), '-',
                          cast(day as varchar(2)))) >= date('2019-09-01')
    ),
    calls as (
        select 
            id_call,
            min(ts_created) as ts_created_min,
            min(ts_created_local) as ts_created_min_local,
            max(ts_created) as ts_created_max,
            max(ts_created_local) as ts_created_max_local            
        from call_events
        group by 1
    ),
    -- Each Teravoz call generates a ticket on Zendesk, if the integration was stable from Semptember 2019, 
    -- we can filter Zendesk tickets from that date.
    zendesk_integration as (
    select
        id_ticket,
        custom_fields,
        ts_updated
    from datalake_clean.zendesk_tickets
    where ts_created >='2019-09-01'
    ),
    -- The table called zendesk_tickets repeats the same ticket for different dates. 
    -- But the last update = max(ts_updated) contains the latest values.
    last_update_tickets as (
        select zt.id_ticket, zt.custom_fields
        from (
            select 
                id_ticket, 
                max(ts_updated) as ts_last_updated 
            from zendesk_integration
            group by 1
        ) last_zt
        inner join (
            select * from zendesk_integration
        ) zt
        on last_zt.id_ticket=zt.id_ticket 
            and last_zt.ts_last_updated=zt.ts_updated
    ),
    zendesk_tickets as (
        select 
            min(id_ticket) as id_ticket, 
            json_extract_scalar(field,'$.value') as id_call
        from last_update_tickets 
        cross join 
            -- custom_fields contains a malformed json so we need to extract its data with regex. 
            unnest(regexp_extract_all(custom_fields, '{[^}]+[^,]+[^{]+}')) as custom(field)
        where
            -- the value "360020220412" correspond to column id that contains the id_call value.
            json_extract_scalar(field, '$.id')='360020220412'
            and json_extract_scalar(field, '$.value')!='null'
        group by 2
    ),
    outside_phone as (
        select
            id_call, 
            json_extract_scalar(metadata, '$.their_number') as outside_phone
        from call_events
        where event='call.new'
        group by 1,2
    ),
    -- gets the user dialed phone (open column values for typing)
    dialed_phone as (
      select 
          id_call, 
          json_extract_scalar(metadata, '$.data') as dialed_phone
      from call_events
      where 
          event='call.data-provided'
          and json_extract_scalar(metadata, '$.tag')='dialed_phone'
          and length(json_extract_scalar(metadata, '$.data'))>=8  -- valid phone size
      group by 1,2
    ),
    -- the max(id) was used to users table from EBDB because a user can have the same phone in the same column. 
    -- returns the most recent user
    -- the phones received by the Teravoz don't have the prefix +55.
    ebdb_main_phone as (
        select 
            max(id) as id,
            replace(main_phone,'+55') as main_phone
        from datalake_ebdb_clean_prod.user
        where main_phone is not null
        group by 2
    ),
    ebdb_secondary_phone as (
        select 
            max(id) as id,
            replace(secondary_phone,'+55') as secondary_phone
        from datalake_ebdb_clean_prod.user
        where secondary_phone is not null
        group by 2
    ),
    ebdb_business_phone as (
        select 
            max(id) as id,
            replace(business_phone,'+55') as business_phone
        from datalake_ebdb_clean_prod.user
        where business_phone is not null
        group by 2
    ),
    ebdb_old_phone as (
        select 
            max(id) as id,
            replace(old_phone,'+55') as old_phone
        from datalake_ebdb_clean_prod.user
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
    ),
    agent_entered_events as (
        select 
            min(id) as id, 
            id_call, 
            agent_email, 
            ts_created, 
            ts_created_local 
        from datalake_bigfone_clean_prod.agent_entered_events 
        where dt_event >= date('2019-09-01')
        group by 2,3,4,5
    ),
    agent_left_events as (
        select 
            id_call, 
            agent_email, 
            ts_created
        from datalake_bigfone_clean_prod.agent_left_events
        where dt_event >= date('2019-09-01')
        group by 1,2,3
    ),
    /*
        talk_time_interactions = time diff between the 'agent_left' event and 'agent_entered' event
        A call can have multiple agent_entered and agent_left events. So we find the pair (entered, left) when:
        1. agent_email is the same 
        2. min(ts_left) >= ts_entered, and ts_left is the closest to ts_entered
        3. id_call is the same
    */
    talk_time as (
        select 
            id_call, 
            sum(date_diff('second',ts_created_entered_event,ts_created_left_event)) as seconds_talk_time
        from (
            select
                enter.id_call,
                enter.ts_created as ts_created_entered_event,
                min(lef.ts_created) as ts_created_left_event
            from agent_entered_events enter
            inner join agent_left_events lef
            on enter.id_call=lef.id_call 
            and enter.agent_email=lef.agent_email
            and lef.ts_created>=enter.ts_created
            group by 1,2
        )
        group by 1 
    ),
    waiting_events as (
        select
            min(id) as id,
            id_call,
            queue_number,
            ts_created,
            ts_created_local
        from datalake_bigfone_clean_prod.call_waiting_events
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
    wait_time as (
        select
            id_call,
            sum(date_diff('second', ts_created_wait_event, ts_created_next_wait_event)) as seconds_wait_time    
        from wait_time_interactions
        group by 1
    ),
    ura as (
        select
            id_call,
            min(ts_created) as ts_first_ura_event,
            min(ts_created_local) as ts_first_ura_event_local,
            max(ts_created) as ts_last_ura_event,
            max(ts_created_local) as ts_last_ura_event_local
        from datalake_bigfone_clean_prod.call_ura_events
        where dt_event >= date('2019-09-01')
        group by 1
    ),
    queues as (
        select
            id_call,
            count(distinct queue_number) as unique_queues_per_call,
            count(distinct id) as queues_per_call
        from wait_time_interactions
        group by 1
    ),
    agents as (
        select
            id_call,
            count(distinct id) as agents_per_call,
            count(distinct agent_email) as unique_agents_per_call,
            min(ts_created) as ts_created_min,
            min(ts_created_local) as ts_created_min_local
        from agent_entered_events
        group by 1
    ),
    agent_ringing_events as (
        select distinct id_call from datalake_bigfone_clean_prod.agent_ringing_events
        where dt_event >= date('2019-09-01')
    ),
    abandoned_queue as (
        select
            id_call,
            queue_number,
            ts_created,
            ts_created_local
        from datalake_bigfone_clean_prod.call_queue_abandon_events
        where dt_event >= date('2019-09-01')
        group by 1,2,3,4
    ),
    call_ring_events as (
        select
            min(id) as id,
            id_call,
            agent_email,
            ts_created,
            ts_created_local
        from datalake_bigfone_clean_prod.agent_ringing_events
        where dt_event >= date('2019-09-01')
        group by 2,3,4,5
    ),
    agent_ring_events as (
        select
            ring.id_call,
            ring.agent_email,
            ring.ts_created_local as ts_min_local
        from call_ring_events ring
        inner join agent_entered_events ae
        on ae.id_call = ring.id_call
            and ae.ts_created > ring.ts_created
        group by 1,2,3
    ),
    ring_summary as (
        select
            are.id_call,
            are.agent_email,
            min(are.ts_min_local) as ts_min_local
        from agent_ring_events are
        group by 1,2
    ),
    call_context_data as (
        select
            id_call,
            json_extract_scalar(metadata, '$.direction') as call_direction
        from call_events
        where event='call.standby' 
            or event='call.new' 
            or event='call.waiting'
            or event='call.ongoing'
            or event='call.finished'
        group by 1,2
    ),
    last_queue_for_agent as (
        select distinct
            wti.id_call,
            max(wti.ts_created_wait_event_local) as ts_created_wait_event_local, 
            max(rs.ts_min_local) as ts_min_local
        from wait_time_interactions wti
        inner join agent_entered_events ae
            on wti.id_call = ae.id_call 
        inner join ring_summary rs 
            on rs.id_call = wti.id_call 
            and rs.agent_email = ae.agent_email
        group by 1
    ),
    last_queued_calls as (
        select distinct
            c.id_call,
            (aq.id_call is not null) as is_call_abandoned_in_queue,
            coalesce(a.unique_agents_per_call>0, false) as is_call_answered_by_agent,
            a.unique_agents_per_call,
            wti.queue_number,
            wti.ts_created_wait_event_local,
            rs.ts_min_local
        from calls c
        inner join agents a 
            on c.id_call = a.id_call 
        left join wait_time_interactions wti
            on wti.id_call = c.id_call
        left join abandoned_queue aq 
            on wti.id_call = aq.id_call 
            and wti.queue_number = aq.queue_number
               inner join agent_entered_events ae
            on wti.id_call = ae.id_call 
        inner join ring_summary rs 
            on rs.id_call = wti.id_call 
    ), 
    distinct_agent_totals as (
        select distinct 
            lq.id_call,
            lq.unique_agents_per_call
        from last_queued_calls lq
        join call_context_data cdc
            on cdc.id_call = lq.id_call
        join last_queue_for_agent lqfa
            on lqfa.id_call = lq.id_call
        where cdc.call_direction = 'inbound' 
        and lq.is_call_answered_by_agent = true 
        and lq.is_call_abandoned_in_queue = false
        and lq.ts_created_wait_event_local = lqfa.ts_created_wait_event_local
        and lq.ts_min_local = lqfa.ts_min_local
    )
select
    c.id_call as sk_call,
    coalesce(out.id_user, dial.id_user) as sk_user,
    cast(zt.id_ticket as bigint) as sk_ticket,
    cast(date_format(c.ts_created_min, '%Y%m%d') as bigint) as sk_call_date,
    cast(date_format(c.ts_created_min_local, '%Y%m%d') as bigint) as sk_call_date_local,
    cast(coalesce(q.queues_per_call,0) as tinyint) as total_queues,
    cast(coalesce(q.unique_queues_per_call,0) as tinyint) as total_unique_queues,
    cast(coalesce(a.agents_per_call,0) as tinyint) as total_agents,
    cast(coalesce(a.unique_agents_per_call, 0) as tinyint) as total_unique_agents,
    cast(date_diff('second', c.ts_created_min, c.ts_created_max) as integer) as seconds_total_call_duration,
    cast(tk.seconds_talk_time as integer) as seconds_total_talk_duration,
    cast(wt.seconds_wait_time as integer) as seconds_total_wait_duration,
    cast(date_diff('second', ura.ts_first_ura_event, ura.ts_last_ura_event) as integer) as seconds_total_ura_duration,
    cast(csat.csat_rating as tinyint) as csat_rating,
    coalesce(a.agents_per_call>0, false) as is_call_answered,
    csat.is_csat_set as is_csat_answered,
    csat.is_call_satisfied_customer,
    coalesce(
        ura.id_call is not null -- calls classified by Akinator don't have ura events 
        and wait.id_call is null -- no call waiting for available agent
        and a.id_call is null -- no agent entered
        and ring.id_call is null, -- no peer ringing
        false
    ) as is_call_ended_in_ura,
    coalesce(
        (wait.id_call is not null or ring.id_call is not null) -- call waiting for available agent or peer ringing
        and a.id_call is null, -- no agent entered
        false
    ) as is_call_missed,
    ura.ts_first_ura_event as ts_ura_joined,
    ura.ts_first_ura_event_local as ts_ura_joined_local,
    ura.ts_last_ura_event as ts_ura_left,
    ura.ts_last_ura_event_local as ts_ura_left_local,
    a.ts_created_min as ts_first_call_answered,
    a.ts_created_min_local as ts_first_call_answered_local,
    coalesce(dat.unique_agents_per_call = 1, False) as is_call_ended_and_answered_by_one_agent,
    coalesce(dat.unique_agents_per_call > 1, False) as is_call_ended_and_answered_by_multiple_agents,
    c.ts_created_min as ts_started,
    c.ts_created_min_local as ts_started_local,
    csat.ts_started as ts_csat_answered,
    csat.ts_started_local as ts_csat_answered_local,
    c.ts_created_max as ts_ended,
    c.ts_created_max_local as ts_ended_local
from calls c
left join zendesk_tickets zt
    on c.id_call=zt.id_call
left join outside_user_phone out
    on c.id_call=out.id_call
left join dialed_user_phone dial
    on c.id_call=dial.id_call
left join talk_time tk
    on c.id_call=tk.id_call
left join wait_time wt
    on c.id_call=wt.id_call
left join ura
    on c.id_call=ura.id_call
left join queues q
    on c.id_call=q.id_call
left join agents a
    on c.id_call=a.id_call
left join datalake_bigfone_clean_prod.call_csat_events csat
    on c.id_call=csat.id_call
left join (select distinct id_call from waiting_events) wait
    on c.id_call=wait.id_call
left join agent_ringing_events ring
    on c.id_call=ring.id_call
left join distinct_agent_totals dat
    on c.id_call=dat.id_call
;