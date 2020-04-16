-- get only the most recent chat loaded
with 
    last_chats_updated as (
        with 
            chat_max_date as (
                select 
                    id,
                    max(
                        concat(
                            string(year), 
                            lpad(string(month), 2, '0'), 
                            lpad(string(day), 2, '0')
                        )
                    ) as ts_load -- YYYYMMDD format
                from datalake_zendesk_clean.chats
                group by 1
            )
        select c.*
        from datalake_zendesk_clean.chats c
        inner join chat_max_date m
        on c.id = m.id
            and m.ts_load = concat(
                    string(c.year), 
                    lpad(string(c.month), 2, '0'), 
                    lpad(string(c.day), 2, '0')
                )
        -- temp full loading
        -- where
        -- year={year} and month={month} and day={day}   
    ),
    -- get only the most recent chat_engagement loaded
    last_chat_engagements_updated as (
        with
            chat_engagements_max_date as (
                select 
                    id,
                    max(
                    concat(
                        string(year), 
                        lpad(string(month), 2, '0'), 
                        lpad(string(day), 2, '0')
                    )
                    ) as ts_load -- YYYYMMDD format
                from datalake_zendesk.chat_engagements
                group by 1
            )
        select ce.*
        from datalake_zendesk.chat_engagements ce
        inner join chat_engagements_max_date m
        on ce.id = m.id
            and m.ts_load = concat(
                    string(ce.year), 
                    lpad(string(ce.month), 2, '0'), 
                    lpad(string(ce.day), 2, '0')
                ) 
    ),
    -- create base table for chats (no rules applied)
    chats as (
        select 
            c.id,
            c.id_ticket,
            cd.name as department_name,
            c.duration,
            c.response_time,
            c.ts_created as ts_created_utc,
            from_utc_timestamp(c.ts_created, 'GMT-3') as ts_created_local,
            c.ts_ended as ts_ended_utc,
            from_utc_timestamp(c.ts_ended, 'GMT-3') as ts_ended_local,
            c.ts_updated
        from last_chats_updated c 
        left join datalake_zendesk_clean.chats_departments as cd
            on c.id_department = cd.id
        group by 1,2,3,4,5,6,7,8,9,10
    ),
    -- create base table for all chats' engagements, including missed (no rules applied)
    engagements as (
        select
            c.id as id_chat,
            ce.id,
            ce.ts_engagement as ts_engagement_started,
            ce.id_agent,
            cd.name as department_name
        from chats c
        left join last_chat_engagements_updated ce
            on c.id = ce.id_chat
            -- Zendesk Insights' official rule for chat engagement metrics
            and not (ce.is_assigned = 'true' and ce.is_accepted = 'false') 
        left join datalake_zendesk_clean.chats_departments as cd
            on cast(ce.id_department as string) = cd.id
        group by 1,2,3,4,5
    ),
    -- get the datetime in which the first engagements (in plural) started
    first_engagements_started as (
        select 
            id_chat,
            min(ts_engagement_started) as ts_first_engagement
        from engagements
        where id is not null
        group by 1
    ),
    -- avoid having two engagements with same ts_engagement_started
    unique_first_engagement as (
        select 
            e.id_chat,
            -- eliminate possible departments with different names
            min(e.department_name) as first_engagement_department
        from first_engagements_started f
        inner join engagements e 
            on e.ts_engagement_started = f.ts_first_engagement
        group by 1
    ),
    -- create table to aggregate and calculate all metrics
    chat_metrics as (
        select
            c.id,
            cast(get_json_object(c.response_time, '$.first') as double) as seconds_first_reply_time,
            round(cast(get_json_object(c.response_time, '$.avg') as double), 2) as seconds_average_reply_time,
            cast(get_json_object(c.response_time, '$.max') as double) as seconds_max_reply_time,
            count(distinct e.id) as number_of_engagements,
            count(distinct e.department_name) as number_of_unique_departments,
            count(distinct e.id_agent) as number_of_unique_agents
        from chats c 
        left join engagements e
            on c.id = e.id_chat
        group by 1,2,3,4
    )
select
	coalesce(nullif(regexp_extract(c.id,'[^.]+$', 0),''),'-1') as sk_chat, --Create key by removing string prefix (year/month + default constant '958463')
	coalesce(c.id_ticket, -1) as sk_ticket,
    cast(date_format(c.ts_created_utc, 'yyyyMMdd') as int) as sk_chat_started_date,
    cast(date_format(c.ts_created_local, 'yyyyMMdd') as int) as sk_chat_started_date_local,
	cast(coalesce(cm.number_of_engagements, 0) as smallint) as number_of_engagements,
	cast(coalesce(cm.number_of_unique_departments, 0) as smallint) as number_of_unique_departments,
	cast(coalesce(cm.number_of_unique_agents, 0) as smallint) as number_of_unique_agents,
	fe.first_engagement_department,
	c.department_name as last_chat_department,
	c.duration as seconds_chat_duration,
	cm.seconds_first_reply_time,
	cm.seconds_average_reply_time,
	cm.seconds_max_reply_time,
	now() as ts_load
from chats c
inner join chat_metrics cm
	on c.id = cm.id
left join unique_first_engagement fe 
	on c.id = fe.id_chat

