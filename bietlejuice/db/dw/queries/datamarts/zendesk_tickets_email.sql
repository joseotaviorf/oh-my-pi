with 
schedule as(
	select
		area,
		to_date(start_date, '%d/%m/%Y') as start_date,
		to_date(end_date, '%d/%m/%Y') as end_date, 
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
)
select 
	dt.sk_ticket,
	dt.ts_created_local,
	cast(dt.ts_created_local as date) as date_request_created,
	date_trunc('hour', dt.ts_created_local) as hour_request_created,
	date_trunc('week', dt.ts_created_local) as week_request_created,
	date_trunc('month', dt.ts_created_local) as month_request_created,
	date_part('hour', dt.ts_created_local) as hour_request_created_int,
	date_part('weekday', dt.ts_created_local) as weekday_request_created_int,
	date_part('month', dt.ts_created_local) as month_request_created_int,
	ft.ts_solved_local,
	ft.ts_closed_local,
	case 
		when ft.ts_solved_local is null then 'not_solved'
		when datediff(hour,dt.ts_created_local, ft.ts_solved_local) between 0 and 1 then 'one_hour'
		when datediff(hour,dt.ts_created_local, ft.ts_solved_local) between 1 and 24 then 'one_day'
		when datediff(hour,dt.ts_created_local, ft.ts_solved_local) between 24 and 168 then 'one_week'
		when datediff(hour,dt.ts_created_local, ft.ts_solved_local) > 168 then 'more_than_one_week'
	end as solved_status,
	ft.minutes_requester_wait_time_business,
	ft.minutes_requester_wait_time_calendar,
    case when cast(ft.minutes_requester_wait_time_business as float)/60.0 <= 8 then 1 else 0 end as sla,
    cast(ft.minutes_requester_wait_time_business as float)/60.0 as rwt_hour,
    ft.replies,
    case
    	when ft.replies > 1 then (cast(ft.minutes_requester_wait_time_business as float)/60.0)/ft.replies 
    	when ft.replies = 0 then cast(ft.minutes_requester_wait_time_business as float)
    end as rwt_per_reply,
    ac.nome as agent_name,
	dt.group_name,
	gdc.area_aux as department,
	gdc.diretoria,
	sc.start_date as schedule_start_date,
	sc.end_date as schedule_end_date,
	sc.start_hour as schedule_start_hour,
	sc.final_hour as schedule_final_hour,
	case
	    when (date_part('hour', dt.ts_created_local) >= sc.start_hour and date_part('hour', dt.ts_created_local) < sc.final_hour) then 1
		else 0
	end as on_schedule
from zendesk.fact_tickets as ft
	join zendesk.dim_ticket as dt
		on dt.sk_ticket = ft.sk_ticket
	left join datalake_raw.gsheets_department_channel as gdc
		on dt.group_name = gdc.aux_canal
	left join datalake_raw.gsheets_agents_control ac 
	    on ac.assignee_id = ft.sk_zendesk_assignee_user
	left join schedule as sc 
		on gdc.area_aux = sc.area and sc.week_day_int = date_part('weekday', dt.ts_created_local)
where dt.channel in ('email', 'form_faq', 'web')
