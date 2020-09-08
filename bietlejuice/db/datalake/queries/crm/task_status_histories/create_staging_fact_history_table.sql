with most_recent_tasks as (
    select
        ct.id,
        max(ct.dt) as max_dt
    from
        datalake_clean.crm_tasks ct
    where
        -- clause that represents the string of which will be replaced by all the automatic task types and manual workgroups
        __WHERE_CLAUSE__
    group by 1
),
actions as (
    select distinct
        ct.id_task as sk_task,
        coalesce(try(cast(try(cast(ct.id_receiver as decimal)) as bigint)), -1) as sk_receiver,
        coalesce(try(cast(try(cast(ct.id_origin as decimal)) as bigint)), -1) as sk_origin,
        coalesce(try(cast(try(cast(ct.id_assignee as decimal)) as bigint)), -1) as sk_assignee,
        coalesce(try(cast(try(cast(ct.id_user_action as decimal)) as bigint)), -1) as sk_user_action,
        coalesce(try(cast(replace(regexp_extract(try(cast(ct.ts_start as varchar)), '\d{4}-\d{2}-\d{2}'), '-', '') as bigint)), -1) as sk_start_date,
        coalesce(try(cast(replace(regexp_extract(try(cast(ct.ts_action as varchar)), '\d{4}-\d{2}-\d{2}'), '-', '') as bigint)), -1) as sk_action_date,
        coalesce(try(cast(replace(regexp_extract(try(cast(ct.ts_previous_action as varchar)), '\d{4}-\d{2}-\d{2}'), '-', '') as bigint)), -1) as sk_task_user_start_date,
        coalesce(try(cast(replace(regexp_extract(try(cast(ct.ts_completed as varchar)), '\d{4}-\d{2}-\d{2}'), '-', '') as bigint)), -1) as sk_completed_date,
        ct.action_user_name,
        ct.action_type,
        ct.action_reason,
        ct.task_status,
        coalesce(
            cast(ct.task_user_resolve_hours as double),
            round(date_diff('second',
                cast(lag(ct.ts_action) over (partition by ct.id_task order by ct.ts_action) as timestamp),
                cast(ct.ts_action as timestamp))/3600.0, 1)
        ) as task_user_resolve_hours,
        ct.ts_action,
        ct.ts_previous_action,
        cast(ct.dt as date) as dt_partition
    from
        datalake_clean.crm_task_resolution_history ct
    join
        most_recent_tasks mrt
            on ct.id_task = mrt.id
            and ct.dt = mrt.max_dt
            and __WHERE_CLAUSE__
),
-- In some cases, the same user can complete the same task more than once.
-- So, only the newest REALIZE or FINISH actions to the CRM models must be used.
most_recent_completed_task_by_user as (
    select
        a.sk_task,
        a.sk_user_action,
        a.sk_task_user_start_date,
        a.sk_action_date,
        a.action_type,
        a.task_user_resolve_hours
        a.ts_previous_action,
        a.ts_action,
        row_number() over (partition by a.sk_task, a.sk_user_action order by a.ts_action desc) as ranking
    from
        actions a
    where
        a.action_type in ('REALIZE', 'FINISH')
        and a.sk_user_action != -1
),
create_start_actions as (
    select
		sk_task,
		min(cast(case when action_type = 'CREATE' then ts_action end as timestamp)) as ts_created_task,
		min(cast(case when action_type = 'START' then ts_action end as timestamp)) as ts_started_task
	from
	    actions
	group by 1
),
tasks as (
    select distinct
        a.sk_task,
        a.sk_receiver,
        a.sk_origin,
        a.sk_assignee,
        a.sk_user_action,
        a.sk_start_date,
        a.sk_completed_date,
        coalesce(mrbu.sk_action_date, a.sk_action_date) as sk_action_date,
        coalesce(mrbu.sk_task_user_start_date, a.sk_task_user_start_date) as sk_task_user_start_date,
        coalesce(mrbu.sk_action_date, a.sk_action_date) as sk_task_user_end_date,
        a.action_user_name,
        a.action_type,
        a.action_reason,
        a.task_status,
        round(date_diff('second', csa.ts_created_task, csa.ts_started_task)/60.0, 1) as minutes_task_created_to_started,
        coalesce(mrbu.task_user_resolve_hours, a.task_user_resolve_hours) as task_user_resolve_hours,
        coalesce(mrbu.ts_action, a.ts_action) as ts_action,
        coalesce(mrbu.ts_previous_action, a.ts_previous_action) as ts_task_user_start,
        coalesce(mrbu.ts_action, a.ts_action) as ts_task_user_end,
        a.dt_partition
    from
        actions a
    left join
        create_start_actions csa
            on a.sk_task = csa.sk_task
    left join
        most_recent_completed_task_by_user mrbu
            on a.sk_task = mrbu.sk_task
            and a.sk_user_action = mrbu.sk_user_action
            and a.action_type = mrbu.action_type
            and mrbu.ranking = 1
    where
        -- due to a bug in CRM, the status REALIZE might have no user attached to it
        -- that scenario should only be possible with the RESOLVE status.
        not(a.sk_user_action = -1 and t.action_type = 'REALIZE')
)
-- append data mart specific CTEs in order to populate its fact table (sqls: append_fact_{data mart})