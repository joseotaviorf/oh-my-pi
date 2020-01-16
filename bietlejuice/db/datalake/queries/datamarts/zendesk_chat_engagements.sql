with 
business_hours as(
	select
		area,
		date(date_parse(start_date, '%d/%m/%Y')) as start_date,
		date(date_parse(end_date, '%d/%m/%Y')) as end_date, 
		cast(start_hour as integer) as start_hour,
		cast(final_hour as integer) as final_hour,
		case 
			when week_day = 'Monday' then 1
			when week_day = 'Tuesday' then 2
			when week_day = 'Wednesday' then 3
			when week_day = 'Thursday' then 4
			when week_day = 'Friday' then 5
			when week_day = 'Saturday' then 6
			when week_day = 'Sunday' then 7
		end as week_day_int
	from datalake_raw.gsheets_department_schedule
),
engagements_parsed as(
	select distinct
		rank() over (partition by ce.id_chat order by cast((from_iso8601_timestamp(ce.ts)) as timestamp) asc) as engagement_order,
		ce.id_chat,
		ce.id,
		cast((from_iso8601_timestamp(ce.ts)) as timestamp) as ts_engagement_started_utc,
		cast((from_iso8601_timestamp(ce.ts) - interval '3' hour) as timestamp) as ts_engagement_started_local,
		cast(ce.duration as double)/60 as engagement_duration_min,
		ce.agent_full_name,
		ce.department_id,
		od.name as department_name,
		gdc.area_aux as area,
		ce.started_by,
		cast(ce.response_time as double)/60,
		case
	  		when (hour(from_iso8601_timestamp(ce.ts) - interval '3' hour) >= bh.start_hour 
	  			and hour(from_iso8601_timestamp(ce.ts) - interval '3' hour) < bh.final_hour) then 1
		else 0
		end as on_schedule
	from datalake_zendesk_raw_prod.chat_engagements as ce
		left join datalake_raw.gsheets_ops_departments as od
			on ce.department_id = od.id
		left join datalake_raw.gsheets_department_channel as gdc
			on od.name = gdc.aux_canal
		left join business_hours bh
			on bh.area = gdc.area_aux and bh.week_day_int = day_of_week(from_iso8601_timestamp(ce.ts) - interval '3' hour)
	where
		date(from_iso8601_timestamp(ce.ts) - interval '3' hour) between bh.start_date and bh.end_date
		and not (ce.assigned = 'true' and ce.accepted = 'false')
)
select
	ep.id,
	ep.id_chat,
	ep.engagement_order,
	ep.ts_engagement_started_local,
	date(ep.ts_engagement_started_local) as dt_engagement_started_local,
	ep.agent_full_name,
	ep.department_name,
	ep.area,
	ep.engagement_duration_min as minutes_engagement_duration,
	ep.on_schedule,
	case when c.dropped = true then 1 else 0 end as chat_dropped,
	case    
	    when ep.engagement_order = 1 and (cast(json_extract(c.response_time, '$.first') as double)/60) <= 15 then 1
	    else 0
	end sla_achieved_15biz_min,
	case    
	    when ep.engagement_order = 1 then (cast(json_extract(c.response_time, '$.first') as double)/60)
	end as minutes_first_response_time
from datalake_zendesk_raw_prod.chats as c
	join engagements_parsed as ep
		on c.id = ep.id_chat
where c.zendesk_ticket_id is not null
