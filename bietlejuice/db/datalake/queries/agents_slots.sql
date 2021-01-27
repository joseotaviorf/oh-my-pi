with
    weekly_schedule_prev as (
        select distinct
            hsa.ts_updated as dt_update,
            id_agent as agent_id,
            day_of_week as dow,
            value as available_slot,
            dat.types as agent_type,
            key as slot_number
        from
            datalake_ebdb_clean_prod.agent_weekly_hours_aud hsa
            join datalake_ebdb_clean_prod.agent_data_types dat
                on hsa.id_agent = dat.id_agent_data
            cross join unnest(
                sequence(0,47),
                array[
                    has_hours_between_08_and_09_available,has_hours_between_08_and_09_available,has_hours_between_08_and_09_available,has_hours_between_08_and_09_available,
                    has_hours_between_09_and_10_available,has_hours_between_09_and_10_available,has_hours_between_09_and_10_available,has_hours_between_09_and_10_available,
                    has_hours_between_10_and_11_available,has_hours_between_10_and_11_available,has_hours_between_10_and_11_available,has_hours_between_10_and_11_available,
                    has_hours_between_11_and_12_available,has_hours_between_11_and_12_available,has_hours_between_11_and_12_available,has_hours_between_11_and_12_available,
                    has_hours_between_12_and_13_available,has_hours_between_12_and_13_available,has_hours_between_12_and_13_available,has_hours_between_12_and_13_available,
                    has_hours_between_13_and_14_available,has_hours_between_13_and_14_available,has_hours_between_13_and_14_available,has_hours_between_13_and_14_available,
                    has_hours_between_14_and_15_available,has_hours_between_14_and_15_available,has_hours_between_14_and_15_available,has_hours_between_14_and_15_available,
                    has_hours_between_15_and_16_available,has_hours_between_15_and_16_available,has_hours_between_15_and_16_available,has_hours_between_15_and_16_available,
                    has_hours_between_16_and_17_available,has_hours_between_16_and_17_available,has_hours_between_16_and_17_available,has_hours_between_16_and_17_available,
                    has_hours_between_17_and_18_available,has_hours_between_17_and_18_available,has_hours_between_17_and_18_available,has_hours_between_17_and_18_available,
                    has_hours_between_18_and_19_available,has_hours_between_18_and_19_available,has_hours_between_18_and_19_available,has_hours_between_18_and_19_available,
                    has_hours_between_19_and_20_available,has_hours_between_19_and_20_available,has_hours_between_19_and_20_available,has_hours_between_19_and_20_available
                ]
            ) as t(key, value)
    ),
    specific_schedule as (
        select distinct
            id_agent as agent_id,
            max(ts_updated) over (partition by id_agent, "dt_agent_specific_hour", key)  as dt_update,
            max_by(is_off_work, ts_updated) over (partition by id_agent, "dt_agent_specific_hour", key) as folga,
            date_add('minute',15 * key, date_add('hour',8, cast("dt_agent_specific_hour" as timestamp))) as slot_dt,
            key as slot_number,
            max_by(value, ts_updated) over (partition by id_agent, "dt_agent_specific_hour", key) as available_slot
        from
            datalake_ebdb_clean_prod.agent_specific_hour_aud 
            cross join unnest(
                sequence(0,47),
                array[
                    is_available_between_08_and_09,is_available_between_08_and_09,is_available_between_08_and_09,is_available_between_08_and_09,
                    is_available_between_09_and_10,is_available_between_09_and_10,is_available_between_09_and_10,is_available_between_09_and_10,
                    is_available_between_10_and_11,is_available_between_10_and_11,is_available_between_10_and_11,is_available_between_10_and_11,
                    is_available_between_11_and_12,is_available_between_11_and_12,is_available_between_11_and_12,is_available_between_11_and_12,
                    is_available_between_12_and_13,is_available_between_12_and_13,is_available_between_12_and_13,is_available_between_12_and_13,
                    is_available_between_13_and_14,is_available_between_13_and_14,is_available_between_13_and_14,is_available_between_13_and_14,
                    is_available_between_14_and_15,is_available_between_14_and_15,is_available_between_14_and_15,is_available_between_14_and_15,
                    is_available_between_15_and_16,is_available_between_15_and_16,is_available_between_15_and_16,is_available_between_15_and_16,
                    is_available_between_16_and_17,is_available_between_16_and_17,is_available_between_16_and_17,is_available_between_16_and_17,
                    is_available_between_17_and_18,is_available_between_17_and_18,is_available_between_17_and_18,is_available_between_17_and_18,
                    is_available_between_18_and_19,is_available_between_18_and_19,is_available_between_18_and_19,is_available_between_18_and_19,
                    is_available_between_19_and_20,is_available_between_19_and_20,is_available_between_19_and_20,is_available_between_19_and_20
                ]
            ) as t(key, value)
    ),
    visits as (
        select distinct a.id_agent as agent_id,
            vo.name,
            date_add('minute',15 * a.slot_day, date_add('hour',8, cast(a.dt_booking as timestamp))) as slot_dt
        from
            datalake_ebdb_clean_prod.booking a
            left join datalake_ebdb_clean_prod.booking_aud aa
                on aa.id = a.id
                and aa.rev_type=0
            left join datalake_ebdb_clean_prod.visit_origin vo
                on vo.id = aa.id_last_update_origin
        where
            a.visit_fup in ('Talvez', 'NaoGostou', 'VaiNegociar', 'VisitouSozinho')
            and a.type = 'Visita'
            and a.dt_booking >= date'2019-01-01'
    ),
    active_history_mod as (
        select distinct
            ure.ts_revision as dt_status,
            coalesce(lag(is_active) over (partition by da.id order by cast(rev as bigint))<>is_active,true) as status_mod,
            da.id,
            da.is_active as status
        from
            datalake_ebdb_clean_prod.agent_data_aud da
            left join datalake_ebdb_user_revision_entity_prod.user_revision_entity ure
                on da.rev = ure.id
    ),
    planner_active as (
        select
            u.id_agent as agent_id,
            date(available_date) as dt_active,
            count(distinct(region_name)) as _count
        from
            datalake_raw.agents_schedule a
            left join datalake_ebdb_clean_prod.user u
                on u.id = cast(a.agent_user_id as bigint)
        group by
            u.id_agent,
            available_date
    ),
    ss_visits as (
        select distinct
            agent_id,
            slot_dt
        from
            visits
        where
            name in ('Inquilinos', 'SelfServiceWeb')
    ),
    full_visits as (
        select distinct
            agent_id,
            slot_dt
        from
            visits
    ),
    weekly_schedule as (
        select
            dt_update,
            agent_id,
            dow,
            available_slot,
            agent_type,
            slot_number,
            lead(dt_update) over (partition by agent_id, dow, slot_number order by dt_update) as dt_next_update,
            lag(available_slot) over (partition by agent_id, dow, slot_number order by dt_update) as previous_status
        from
            weekly_schedule_prev
    ),
    schedule_versions as (
        select
            agent_id,
            agent_type,
            dt_update,
            cast(dow as bigint) as dow,
            available_slot,
            lead(dt_update) over ( partition by agent_id, dow, slot_number order by dt_update) as dt_next_update,
            slot_number
        from
            weekly_schedule
        where
            coalesce((previous_status <> available_slot), true) = true
    ),
    base_time as (
        select
            cast(date_column AS timestamp) as dt,
            dow(cast(date_column AS timestamp)) as dow,
            date_diff('minute', date_trunc('day', cast(date_column AS timestamp)) + interval '8' hour, cast(date_column AS timestamp))/15 as slot_number
        from
            (
            values(sequence(from_iso8601_date('2019-01-01'),current_date + interval '2' month, interval '15' minute))
            ) AS t1(date_array)
            cross join unnest(date_array) as t2(date_column)
        where
            hour(cast(date_column AS timestamp)) between 7 and 21
            and cast(date_column AS timestamp) >= cast('2019-01-01' AS timestamp)
    ),
    base_schedule as (
        select
            agent_id,
            agent_type,
            su.dt_update,
            dd.dt as slot_dt,
            su.dow,
            su.slot_number,
            su.available_slot
        from
            schedule_versions su
        left join base_time dd
            on dd.dt > date_trunc('minute', dt_update)
            and dd.dt <= date_trunc('minute',coalesce(su.dt_next_update, current_date + interval '1' month))
            and dd.slot_number = su.slot_number
            and dd.dow = su.dow
        where
            dd.dt is not null
    ),
    active_history as (
        select
            dt_status as min_version_time,
            coalesce(lead(dt_status) over (partition by id order by dt_status),date('2300-01-01')) as max_version_time,
            status,
            id as agent_id
        from
            active_history_mod ahm
        where
            ahm.status_mod = true
    ),
    specific_updates as (
        select
            bs.agent_id,
            bs.agent_type,
            bs.dt_update as last_weekly_update,
            case
                when ss.available_slot is not null and ss.available_slot <> bs.available_slot then ss.dt_update
                else null
            end as last_specific_update,
            bs.slot_dt,
            bs.dow,
            bs.slot_number,
            bs.available_slot as original_slot,
            case
                when ss.folga = true and ss.available_slot <> bs.available_slot then '0'
                when ss.available_slot is not null and ss.available_slot <> bs.available_slot then cast(ss.available_slot as varchar)
                else cast(bs.available_slot as varchar)
            end as available_slot,
            case
                when ss.folga = true and ss.available_slot <> bs.available_slot then 'day off'
                when ss.available_slot is not null and ss.available_slot <> bs.available_slot then 'specific'
                else null
            end as last_change_reason,
            case
                when ss.folga = true and ss.available_slot <> bs.available_slot then true
                when ss.available_slot is not null and ss.available_slot <> bs.available_slot then true
                else false
            end as specific_update
        from
            base_schedule bs
            left join specific_schedule ss
                on bs.agent_id = ss.agent_id
                and bs.slot_dt = ss.slot_dt
    ),
    time_window_updates as (
        select
            sc.agent_id,
            sc.agent_type,
            sc.last_weekly_update,
            sc.last_specific_update,
            sc.slot_dt,
            sc.dow,
            sc.slot_number,
            sc.original_slot,
            sc.available_slot as specific_slot,
            case
                when available_slot = '1' and date_diff('hour', coalesce(last_specific_update, last_weekly_update), slot_dt) < 96
                then '0'
                else available_slot
            end as available_slot,
            case
                when available_slot = '1' and date_diff('hour', coalesce(last_specific_update, last_weekly_update), slot_dt) < 96
                then '96 hours'
                else sc.last_change_reason
            end as last_change_reason,
            specific_update,
            case
                when available_slot = '1' and date_diff('hour', coalesce(last_specific_update, last_weekly_update), slot_dt) < 96
                then true
                else false
            end as time_window_update,
            case
                when available_slot = '1' and date_diff('hour', coalesce(last_specific_update, last_weekly_update), slot_dt) < 24
                then '0'
                else available_slot
            end as available_slot_24h
        from
            specific_updates sc
    ),
    visits_updates as (
        select
            tw.agent_id,
            tw.agent_type,
            tw.last_weekly_update,
            tw.last_specific_update,
            tw.slot_dt,
            tw.dow,
            tw.slot_number,
            tw.original_slot,
            tw.specific_slot,
            tw.available_slot as time_slot,
            case
                when (sv.agent_id is not null) then '1'
                when lag((sv.agent_id is not null)) over (partition by tw.agent_id order by tw.slot_dt) then '1'
                else tw.available_slot
            end as ss_available_slot,
            case
                when (fv.agent_id is not null) then '1'
                when lag((fv.agent_id is not null)) over (partition by tw.agent_id order by tw.slot_dt) then '1'
                else tw.available_slot
            end as available_slot,
            (fv.agent_id is not null) as has_visit,
            (sv.agent_id is not null) as self_service_visit,
            case
                when (fv.agent_id is not null) and tw.available_slot = '0' then 'visit'
                when lag((fv.agent_id is not null)) over (partition by tw.agent_id order by tw.slot_dt) and tw.available_slot = '0' then 'visit'
                else tw.last_change_reason
            end as last_change_reason,
            specific_update,
            time_window_update,
            case
                when (fv.agent_id is not null) and tw.available_slot = '0' then true
                when lag((fv.agent_id is not null)) over (partition by tw.agent_id order by tw.slot_dt) and tw.available_slot = '0' then true
                else false
            end as visit_update,
                    case
                when (fv.agent_id is not null) then '1'
                when lag((fv.agent_id is not null)) over (partition by tw.agent_id order by tw.slot_dt) then '1'
                else tw.available_slot_24h
            end as available_slot_24h
        from
            time_window_updates tw
            left join ss_visits sv
                on sv.agent_id = tw.agent_id
                and sv.slot_dt = tw.slot_dt
            left join full_visits fv
                on fv.agent_id = tw.agent_id
                and fv.slot_dt = tw.slot_dt
    )
select
    vu.agent_id,
    vu.agent_type,
    vu.last_weekly_update,
    vu.last_specific_update,
    vu.slot_dt,
    vu.dow,
    vu.slot_number,
    cast(cast(vu.ss_available_slot as boolean) as integer) as ss_available_slot,
    cast(cast(vu.available_slot as boolean) as integer) as available_slot,
    cast(cast(vu.available_slot_24h as boolean) as integer) as available_slot_24h,
    vu.specific_update,
    vu.time_window_update,
    vu.visit_update,
    vu.has_visit,
    vu.self_service_visit,
    vu.last_change_reason,
    cast(ah.status as integer) as history_status,
    case when pa._count > 0 then '1' else '0' end as planner_status,
    cast(cast(vu.specific_slot as boolean) as integer) as specific_slot
from
    visits_updates vu
    left join active_history ah
        on ah.agent_id = vu.agent_id
        and vu.slot_dt between ah.min_version_time and ah.max_version_time
    left join planner_active pa
        on pa.agent_id = vu.agent_id
        and pa.dt_active = date(vu.slot_dt)
where
    date(vu.slot_dt) between date('{dt}') and date('{dt}') + interval '21' day
    and ah.status = true;