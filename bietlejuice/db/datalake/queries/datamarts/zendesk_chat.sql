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
		ce.id_chat,
		ce.id,
		cast((from_iso8601_timestamp(ce.ts)) as timestamp) as ts_engagement_started_utc,
		cast((from_iso8601_timestamp(ce.ts) - interval '3' hour) as timestamp) as ts_engagement_started_local,
		cast(ce.duration as double)/60 as engagement_duration_min,
		ac.nome as agent_full_name,
		ac.gestores as manager,
		ac.centro_de_custo as cost_center,
		ce.department_id,
		cd.name as department_name,
		gdc.area_aux as area,
		ce.started_by,
		case
	  		when (hour(from_iso8601_timestamp(ce.ts) - interval '3' hour) >= bh.start_hour 
	  			and hour(from_iso8601_timestamp(ce.ts) - interval '3' hour) < bh.final_hour) then 1
	  		when (hour(from_iso8601_timestamp(ce.ts) - interval '3' hour) < bh.start_hour 
	  			and hour(from_iso8601_timestamp(ce.ts) - interval '3' hour) >= bh.final_hour) then 0
		end as on_schedule
	from datalake_zendesk_clean_prod.chat_engagements as ce
		left join datalake_zendesk_clean_prod.chats_departments as cd
			on try_cast(ce.department_id as bigint) = cd.id
		left join datalake_raw.gsheets_department_channel as gdc
			on cd.name = gdc.aux_canal
		left join datalake_raw.gsheets_agents_control ac
	    		on ac.assignee_id = ce.agent_id
		left join business_hours bh
			on bh.area = gdc.area_aux and bh.week_day_int = day_of_week(from_iso8601_timestamp(ce.ts) - interval '3' hour)
				and date(from_iso8601_timestamp(ce.ts) - interval '3' hour) between bh.start_date and bh.end_date
	where not (ce.assigned = 'true' and ce.accepted = 'false')
),
chat_engagements as (
	select distinct
		*,
		row_number() over (partition by ep.id_chat order by ts_engagement_started_local asc) as engagement_order,
		count(ep.id) over (partition by ep.id_chat) as total_engagements
	from engagements_parsed as ep
),
chat_zendesk as (
	select distinct
		c.id,
		c.id_ticket as zendesk_ticket_id,
		c.ts_created as ts_chat_started,
		c.ts_created - interval '3' hour as ts_chat_started_local,
		c.department_name,
		gdc.area_aux as chat_area,
		c.tags,
		c.is_missed,
		c.is_dropped,
		c.duration,
		c.response_time,
		case
	  		when (hour(c.ts_created - interval '3' hour) >= bh.start_hour
	  			and hour(c.ts_created - interval '3' hour) < bh.final_hour) then 1
	  		when (hour(c.ts_created - interval '3' hour) < bh.start_hour
	  			and hour(c.ts_created - interval '3' hour) >= bh.final_hour) then 0
		end as chat_on_schedule,
		c.visitor,
   		json_extract_scalar(c.visitor, '$.phone') as visitor_phone
	from datalake_zendesk_clean_prod.chats as c
		left join datalake_raw.gsheets_department_channel as gdc
			on c.department_name = gdc.aux_canal
		left join business_hours bh
			on bh.area = gdc.area_aux and bh.week_day_int = day_of_week(c.ts_created - interval '3' hour)
				and date(c.ts_created - interval '3' hour) between bh.start_date and bh.end_date
	where id_ticket is not null
)
select distinct
	c.id as id_chat,
	c.zendesk_ticket_id,
	c.ts_chat_started_local as ts_started_local,
	date(c.ts_chat_started_local) as dt_started_local,
	ce.department_name as first_engagement_department,
	ce.area as first_engagement_area,
    c.department_name as last_chat_department,
    c.chat_area as last_chat_area,
	case
        when c.tags like '%bot_end_conversation%' then 1
        else 0
    end as bot_end_conversation,
    c.tags,
    ce.total_engagements,
    case
    	when ce.on_schedule = 1 or c.chat_on_schedule = 1 then 1
    	when ce.on_schedule is null and c.chat_on_schedule is null
    		then
	    		(case
					when (day_of_week(c.ts_chat_started_local) between 1 and 5
				        and hour(c.ts_chat_started_local) >= 8
					    and hour(c.ts_chat_started_local) < 19)
				    or (day_of_week(c.ts_chat_started_local) = 6
				        and hour(c.ts_chat_started_local) >= 9
					    and hour(c.ts_chat_started_local) < 14) then 1
				else 0 end)
    	else 0
    end as is_business_hours,
	case when c.is_missed = true and c.tags not like '%bot_end_conversation%' then 1 else 0 end as missed,
	case when c.is_dropped = true then 1 else 0 end as dropped,
	cast(c.duration as double) as seconds_chat_duration,
	cast(json_extract(c.response_time, '$.first') as double)/60 as minutes_first_response_time,
	case
	    when (cast(json_extract(c.response_time, '$.first') as double)/60) <= 15 then 1
	    when (cast(json_extract(c.response_time, '$.first') as double)/60) > 15 then 0
	    else null
	end sla_achieved_15biz_min,
	c.visitor,
	c.visitor_phone
from chat_zendesk as c
	left join chat_engagements as ce
		on c.id = ce.id_chat and ce.engagement_order = 1
