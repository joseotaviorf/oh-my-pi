drop view if exists zendesk.vw_post_contract_ticket_full_resolution_time;
create view zendesk.vw_post_contract_ticket_full_resolution_time as
select distinct
	t.created_at::date as dt_created,
	date_part('day', t.created_at) as _day,
	date_part('week', t.created_at) as _week,
	date_part('month', t.created_at) as _month,
	date_part('year', t.created_at) as _year,
	avg(tm.full_resolution_time_in_minutes_business::decimal(10,4)/60)
		filter (where tm.full_resolution_time_in_minutes_business > 0 )
		over (partition by t.created_at::date) as daily_avg,
	avg(tm.full_resolution_time_in_minutes_business::decimal(10,4)/60)
		filter (where tm.full_resolution_time_in_minutes_business > 0 )
		over (partition by date_part('week', t.created_at), date_part('year', t.created_at)) as weekly_avg,
	avg(tm.full_resolution_time_in_minutes_business::decimal(10,4)/60)
		filter (where tm.full_resolution_time_in_minutes_business > 0 )
		over (partition by date_part('month', t.created_at), date_part('year', t.created_at)) as monthly_avg,
	avg(tm.full_resolution_time_in_minutes_business::decimal(10,4)/60)
		filter (where tm.full_resolution_time_in_minutes_business > 0 )
		over (partition by date_part('year', t.created_at)) as yearly_avg,
	avg(tm.full_resolution_time_in_minutes_business::decimal(10,4)/60)
		filter (
			where tm.full_resolution_time_in_minutes_business > 0
			and date_part('year', t.created_at) = date_part('year', (current_date - interval '1 week')::date)
  		and date_part('month', t.created_at) = date_part('month', (current_date - interval '1 week')::date)
  		and date_part('day', t.created_at) <= date_part('day', (current_date - interval '1 week')::date)
		) over () as last_week_avg,
	avg(tm.full_resolution_time_in_minutes_business::decimal(10,4)/60)
		filter (
			where tm.full_resolution_time_in_minutes_business > 0
			and date_part('year', t.created_at) = date_part('year', (current_date - interval '1 month')::date)
  		and date_part('month', t.created_at) = date_part('month', (current_date - interval '1 month')::date)
  		and date_part('day', t.created_at) <= date_part('day', current_date)
		) over () as last_month_avg,
	avg(tm.full_resolution_time_in_minutes_business::decimal(10,4)/60)
		filter (
			where tm.full_resolution_time_in_minutes_business > 0
			and date_part('year', t.created_at) = date_part('year', (current_date - interval '12 month')::date)
  		and date_part('month', t.created_at) = date_part('month', (current_date - interval '12 month')::date)
  		and date_part('day', t.created_at) <= date_part('day', (current_date - interval '12 month')::date)
		) over () as last_year_avg
from
	zendesk.ticket t
left join
	zendesk."group" g
	on t.group_id = g.id
left join
	zendesk.via v
	on t.via_id = v.id
left join
	zendesk.ticket_metrics tm
	on t.id = tm.ticket_id
where g."name" in
	(
		'ADM Casos',
		'ADM Mediações',
		'ADM Offboarding',
		'ADM Onboarding',
		'ADM Renovação',
		'ADM Rescisão',
		'CX Administração',
		'CX Pós',
		'Casos Especiais',
		'Collections',
		'Crise',
		'Payments Tasks',
		'Vistoria'
	)
	and is_whatsapp = false
	and t.status in ('closed', 'solved')
	and t.created_at >= '2017-01-01'
;