-- partition chats
with filtered_chats as (
	select
		*
	from datalake_zendesk.chat_engagements
	-- temp full loading
	-- where
  	-- 	year={year} and month={month} and day={day}
),
chat_engagement_max_date as (
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
),
-- create base table for chat engagements (no rules applied)
chat_engagements as (
	select 
		ce.id,
		cd.name as department_name,
		ce.started_by,
        cast(round(ce.duration) as integer) as duration,
		ce.ts_started_utc,
		ce.ts_started_local,
		ce.ts_ended_utc,
		ce.ts_ended_local
	from filtered_chats ce 
	inner join chat_engagement_max_date m 
		on ce.id = m.id
		and m.ts_load = concat(
            string(year), 
            lpad(string(month), 2, '0'), 
            lpad(string(day), 2, '0')
           )
	left join datalake_zendesk_clean.chats_departments as cd
		on ce.id_department = cd.id
	where not (ce.is_assigned = true and ce.is_accepted = false) -- Zendesk Insights' official rule for chat engagement metrics
	group by 1,2,3,4,5,6,7,8
)
select
	coalesce(nullif(regexp_extract(ce.id, '[^.]+.\\w+$', 0),''),'-1') as sk_chat_engagement, --Create key by removing string prefix
	ce.started_by,
	ce.ts_started_utc as ts_started,
	ce.ts_started_local,
    ce.ts_ended_utc as ts_ended,
    ce.ts_ended_local,
	now() as ts_load
from chat_engagements as ce
