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
		else 0
		end as on_schedule
	from datalake_zendesk_raw_prod.chat_engagements as ce
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
	select
		row_number() over (partition by ep.id_chat order by ts_engagement_started_local asc) as engagement_order,
		*
	from engagements_parsed as ep
)
select distinct
	ce.id,
	ce.id_chat,
	ce.engagement_order,
	ce.ts_engagement_started_local,
	date(ce.ts_engagement_started_local) as dt_engagement_started_local,
	ce.started_by,
	ce.agent_full_name,
	ce.manager,
	ce.cost_center,
	ce.department_name,
	ce.area,
	ce.engagement_duration_min as minutes_engagement_duration,
	ce.on_schedule as is_business_hours
from datalake_zendesk_raw_prod.chats as c
	join chat_engagements as ce
		on c.id = ce.id_chat
where c.zendesk_ticket_id is not null
