with cancellation_info as (
    with cancelled_jobs_max_rev as (
        select
            id_photographer_job,
            max(rev) as rev
        from datalake_ebdb_clean.photographer_job_aud
        where status = 'Cancelado' and mod_status
        group by 1
    ),
    cancellation_reason as (
        with house_reg_status_max_rev as (
            select
                id_photo_shoot,
                max(rev) as rev
            from datalake_ebdb_clean.house_registration_status_aud
            group by 1
        )
        select
            hrsmr.id_photo_shoot,
            hrs.photo_shoot_schedule_reason
        from house_reg_status_max_rev hrsmr
        join datalake_ebdb_clean.house_registration_status_aud hrs
            on hrsmr.rev = hrs.rev
    )
    select
        pj.id as id_photographer_job,
        ure.id as id_revision,
        user.id_photographer_data,
        user.id_sales_rep,
        user.id as id_user_who_canceled,
        user.name as user_who_canceled_name,
        user.email as user_who_canceled_email,
        coalesce(pj.reason_of_change, cr.photo_shoot_schedule_reason) as cancellation_reason,
        ure.ts_revision
    from datalake_ebdb_clean.photographer_job pj
    left join cancelled_jobs_max_rev cjmr
        on cjmr.id_photographer_job = pj.id
    join datalake_ebdb_user_revision_entity.user_revision_entity ure
        on ure.id = cjmr.rev
    join datalake_ebdb_clean.user
        on user.id = ure.id_user
    left join cancellation_reason cr
        on cr.id_photo_shoot = pj.id
),
problems_info as (
    with jobs_with_problem_max_rev as (
        select
            id_photographer_job,
            max(rev) as rev
        from datalake_ebdb_clean.photographer_job_aud
        where status = 'ComProblema' and mod_status
        group by 1
    )
    select
        pjmr.id_photographer_job,
        ure.ts_revision
    from jobs_with_problem_max_rev pjmr
    join datalake_ebdb_user_revision_entity.user_revision_entity ure
        on ure.id = pjmr.rev
),
photographer_data as (
    select
        pd.id as id_photographer_data,
        user.id as id_photographer,
        user.name as photographer_name,
        user.email as photographer_email,
        pd.ts_created as dt_photographer_started
    from datalake_ebdb_clean.user
    left join datalake_ebdb_clean.photographer_data pd
        on pd.id = user.id_photographer_data
),
job_creator_info as (
    with jobs_min_rev as (
        select
            id_photographer_job,
            min(rev) as rev
        from datalake_ebdb_clean.photographer_job_aud
        group by 1
        )
    select
        jmr.id_photographer_job,
        creator.id as id_user,
        creator.id_photographer_data,
        creator.id_sales_rep,
        creator.email
    from jobs_min_rev jmr
    join datalake_ebdb_user_revision_entity.user_revision_entity ure
        on ure.id = jmr.rev
    join datalake_ebdb_clean.user creator
        on creator.id = ure.id_user
)
select
        f.id,
        f.id_house,
        photographer_data.id_photographer,
        cancellation_info.id_user_who_canceled,
        case
            when job_creator_info.id_sales_rep is not null then job_creator_info.id_user
            else null
        end as id_rep,
        f.status as job_status,
        f.booking_instructions,
        photographer_data.photographer_name,
        photographer_data.photographer_email,
        f.photo_session_contact_name,
        f.photo_session_email,
        f.photo_session_phone,
        f.photo_session_secondary_phone,
        f.key_pick_up,
        f.key_others,
        f.contract_type,
        f.problem,
        f.photo_sender_user_type,
        cancellation_info.cancellation_reason,
        f.cancellation_reason_text,
        cancellation_info.user_who_canceled_name,
        cancellation_info.user_who_canceled_email,
        case
            when job_creator_info.id_photographer_data is not null and job_creator_info.id_sales_rep is not null then 'Teste'
            when job_creator_info.id_photographer_data is not null then 'Fotografo'
            when job_creator_info.id_sales_rep is not null then 'InsideSales_internal'
            when job_creator_info.email like '%actionline%' then 'InsideSales_external'
            when job_creator_info.email like '%quintoandar%' then 'Admin'
            else 'Prop'
        end as creation_origin,
        case
            when f.status != 'Cancelado' then null
            when cancellation_info.id_photographer_data is not null and cancellation_info.id_sales_rep is not null then 'Teste'
            when cancellation_info.id_photographer_data is not null then 'Fotografo'
            when job_creator_info.id_sales_rep is not null then 'InsideSales_internal'
            when job_creator_info.email like '%actionline%' then 'InsideSales_external'
            when cancellation_info.user_who_canceled_email like '%quintoandar%' then 'Admin'
            when cancellation_info.id_revision is null then null
            else 'Prop'
        end as user_cancellation_type,
        f.has_lockbox,
        (f.status == 'Cancelado') as is_canceled,
        f.is_approved,
        f.is_confirmed,
        !(f.ts_scheduled is null or (hour(f.ts_scheduled) between 6 and 23)) as is_flexible_schedule,
        -- same_day_upload applies to any upload until 8 AM (5AM - due to UTC diff) of the next day after the photo shoot
        coalesce((f.ts_photos_uploaded <= cast(cast(coalesce(f.ts_session_started, f.ts_scheduled) as date) as timestamp) + interval '1' day + interval '8' hour), false) as is_same_day_upload,
        -- job_on_time applies to any upload until 8 AM (5AM - due to UTC diff) of the next day after the photo shoot scheduled date
        coalesce((f.ts_photos_uploaded <= cast(cast(f.ts_scheduled as date) as timestamp) + interval '1' day + interval '8' hour), false) as is_job_on_time,
        -- job anticipated applies to any photo job uploaded on D-1 or earlier in relation to its scheduled date
        coalesce((date_format(f.ts_photos_uploaded,'yyyyMMdd') < date_format(date(f.ts_scheduled),'yyyyMMdd')), false) as is_job_anticipated,
        (
            (
                unix_timestamp(
                    case
                        when hour(f.ts_scheduled) between 6 and 23 then f.ts_scheduled
                        when  cast(cast(f.ts_scheduled as date) as timestamp) + interval '12' hour < f.ts_created then f.ts_created
                        else  cast(cast(f.ts_scheduled as date) as timestamp) + interval '12' hour
                    end
                ) - unix_timestamp(f.ts_created)
            )/60000
        ) as creation_to_scheduling_diff_minutes,
        photographer_data.dt_photographer_started,
        f.ts_photographer_accepted,
        f.ts_photo_job_requested,
        f.ts_session_started,
        f.ts_scheduled,
        f.ts_photos_uploaded,
        cancellation_info.ts_revision as ts_problem_reported,
        problems_info.ts_revision as ts_canceled,
        f.ts_created,
        f.ts_updated
    from datalake_ebdb_clean.photographer_job f
    left join cancellation_info
        on cancellation_info.id_photographer_job = f.id
        and f.status = 'Cancelado' -- TODO [ODS] This and appears to be redundant. Since we filter by status in the cte, this is not present in the join below neither
    left join problems_info
        on problems_info.id_photographer_job = f.id
    left join photographer_data
        on photographer_data.id_photographer_data = f.id_photographer_data
    left join job_creator_info
        on job_creator_info.id_photographer_job = f.id
