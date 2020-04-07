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
		ce.id_chat,
		ce.id_department,
		ce.id_agent,
		ce.ts_started_utc,
		ce.ts_started_local,
		ce.duration
	from filtered_chats ce
	inner join chat_engagement_max_date m 
		on ce.id = m.id
		and m.ts_load = concat(
            string(year), 
            lpad(string(month), 2, '0'), 
            lpad(string(day), 2, '0')
           )
	where not (ce.is_assigned = true and ce.is_accepted = false) -- Zendesk Insights' official rule for chat engagement metrics
	group by 1,2,3,4,5,6,7
),
calculate_first_last as (
	select 
		id_chat,
		min(ts_started_utc) as ts_first_chat_engagement,
		max(ts_started_utc) as ts_last_chat_engagement
	from chat_engagements
	group by 1
)
select
	coalesce(nullif(regexp_extract(ce.id, '[^.]+.\\w+$', 0),''),'-1') as sk_chat_engagement, --Create key by removing string prefix
	coalesce(nullif(regexp_extract(ce.id_chat, '[^.]+$', 0),''),'-1') as sk_chat, --Create key getting everything after final '.'
	coalesce(cast(ce.id_department as bigint), -1) as sk_engagement_department,
	coalesce(cast(ce.id_agent as bigint), -1) as sk_zendesk_agent,
	cast(date_format(ce.ts_started_utc, 'yyyyMMdd') as bigint) as sk_engagement_started_date,
	cast(date_format(ce.ts_started_local,'yyyyMMdd') as bigint) as sk_engagement_started_date_local,
	case when ce.ts_started_utc = fl.ts_first_chat_engagement then true else false end as is_first_engagement_in_chat,
	case when ce.ts_started_utc = fl.ts_last_chat_engagement then true else false end as is_last_engagement_in_chat,
	round(cast(ce.duration as double), 2) as seconds_engagement_duration,
	now() as ts_load
from chat_engagements as ce
inner join calculate_first_last as fl
	on ce.id_chat = fl.id_chat
