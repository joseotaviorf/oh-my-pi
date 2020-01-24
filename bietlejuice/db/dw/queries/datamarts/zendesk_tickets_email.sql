select 
	dt.sk_ticket,
	dt.ts_created_local,
	ft.ts_solved_local,
	ft.ts_closed_local,
	trunc(dt.ts_created_local) as dt_created_local,
	trunc(ft.ts_solved_local) as dt_solved_local,
	trunc(ft.ts_closed_local) as dt_closed_local,
	case when ft.ts_solved_local is not null then 1 else 0 end as is_solved,
	case 
		when ft.ts_solved_local is null then 'not_solved'
		when datediff(hour,dt.ts_created_local, ft.ts_solved_local) between 0 and 1 then 'one_hour'
		when datediff(hour,dt.ts_created_local, ft.ts_solved_local) between 1 and 24 then 'one_day'
		when datediff(hour,dt.ts_created_local, ft.ts_solved_local) between 24 and 168 then 'one_week'
		when datediff(hour,dt.ts_created_local, ft.ts_solved_local) between 168 and 720 then 'one_month'
		when datediff(hour,dt.ts_created_local, ft.ts_solved_local) > 720 then 'more_than_one_month'
	end as solved_status,
	case when dzu.role = 'agent' then 1 else 0 end as is_created_by_agent,
	ac.nome as agent_name,
	ac.gestores as manager,
	ac.centro_de_custo as cost_center,
	dt.group_name,
	gdc.area_aux as department,
    ft.replies,
    ft.minutes_first_reply_time_business,
	ft.minutes_requester_wait_time_business,
	ft.minutes_requester_wait_time_calendar,
	ft.minutes_full_resolution_time_business,
    case when cast(ft.minutes_first_reply_time_business as float)/60.0 <= 8 then 1 else 0 end as sla_achieved_8biz_hr,
    cast(ft.minutes_requester_wait_time_business as float)/60.0 as hours_requester_wait_time_business,
    case
    	when ft.replies > 1 then (cast(ft.minutes_requester_wait_time_business as float)/60.0)/ft.replies 
    	when ft.replies = 0 then cast(ft.minutes_requester_wait_time_business as float)
    end as rwt_per_reply,
    case 
	    when dt.tags ilike '%resolve_ticket_acompanhamento%' or
        	dt.tags ilike '%fechado_automaticamente_noreply%' or
        	dt.tags ilike '%redirecionado_atendimento_2%' or
        	dt.tags ilike '%closed_by_merge%' or
        	dt.tags ilike '%zapdesk%' or
        	dt.tags ilike '%ticket_via_call%' or
        	dt.tags ilike '%call_contato_receptivo%' or
        	dt.tags ilike '%call_contato_ativo%' or
        	dt.tags ilike '%resolve_ticket_acompanhamento%' or
        	dt.tags ilike '%redirecionado_adm_v1%'
        	then 1 
    	else 0 
	end as exclude_tags,
    dt.tags
from zendesk.fact_tickets as ft
	join zendesk.dim_ticket as dt
		on dt.sk_ticket = ft.sk_ticket
	left join zendesk.dim_zendesk_user as dzu
		on ft.sk_zendesk_submitter_user = dzu.sk_zendesk_user
	left join datalake_raw.gsheets_department_channel as gdc
		on dt.group_name = gdc.aux_canal
	left join datalake_raw.gsheets_agents_control ac 
	    on ac.assignee_id = ft.sk_zendesk_assignee_user
where dt.channel in ('email', 'form_faq', 'web')
