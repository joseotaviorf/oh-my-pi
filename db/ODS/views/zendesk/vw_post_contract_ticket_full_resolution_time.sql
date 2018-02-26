drop view if exists zendesk.vw_post_contract_ticket_full_resolution_time;
create or replace view zendesk.vw_post_contract_ticket_full_resolution_time as
select distinct
	t.created_at::date as dt_created,
	date_part('day', t.created_at)::integer as _day,
	date_part('week', t.created_at)::integer as _week,
	date_part('month', t.created_at)::integer as _month,
	date_part('year', t.created_at)::integer as _year,
	(
	coalesce(sum(case when (tm.full_resolution_time_in_minutes_calendar/60)<48 then 1 else 0 end)
		filter (where tm.full_resolution_time_in_minutes_calendar > 0  and t.status in ('closed', 'solved'))
		over (partition by t.created_at::date)::decimal(10,4), 0)
	/ nullif(count(1)
		over (partition by t.created_at::date), 0)
	)::decimal(10,4) as daily_percentage,
	(
	coalesce(sum(case when (tm.full_resolution_time_in_minutes_calendar/60)<48 then 1 else 0 end)
		filter (where tm.full_resolution_time_in_minutes_calendar > 0  and t.status in ('closed', 'solved'))
		over (partition by date_part('week', t.created_at), date_part('year', t.created_at))::decimal(10,4), 0)
	/ nullif(count(1)
		over (partition by date_part('week', t.created_at), date_part('year', t.created_at)), 0)
	)::decimal(10,4) as weekly_percentage,
	(
	coalesce(sum(case when (tm.full_resolution_time_in_minutes_calendar/60)<48 then 1 else 0 end)
		filter (where tm.full_resolution_time_in_minutes_calendar > 0  and t.status in ('closed', 'solved'))
		over (partition by date_part('month', t.created_at), date_part('year', t.created_at))::decimal(10,4), 0)
	/ nullif(count(1)
		over (partition by date_part('month', t.created_at), date_part('year', t.created_at)), 0)
	)::decimal(10,4) as monthly_percentage,
	(
	coalesce(sum(case when (tm.full_resolution_time_in_minutes_calendar/60)<48 then 1 else 0 end)
		filter (where tm.full_resolution_time_in_minutes_calendar > 0  and t.status in ('closed', 'solved'))
		over (partition by date_part('year', t.created_at))::decimal(10,4), 0)
	/ nullif(count(1)
		over (partition by date_part('year', t.created_at)), 0)
	)::decimal(10,4) as yearly_percentage,
	(coalesce(sum(case when (tm.full_resolution_time_in_minutes_calendar/60)<48 then 1 else 0 end)
	filter (
			where tm.full_resolution_time_in_minutes_calendar > 0  and t.status in ('closed', 'solved')
			and date_part('year', t.created_at) = date_part('year', (current_date - interval '1 week')::date)
  		and date_part('month', t.created_at) = date_part('month', (current_date - interval '1 week')::date)
  		and date_part('day', t.created_at) < date_part('day', (current_date - interval '1 week')::date)
		)
	over ()::decimal(10,4), 0)  / nullif(count(1)
	filter (
			where date_part('year', t.created_at) = date_part('year', (current_date - interval '1 week')::date)
  		and date_part('month', t.created_at) = date_part('month', (current_date - interval '1 week')::date)
  		and date_part('day', t.created_at) < date_part('day', (current_date - interval '1 week')::date)
		)
	over (), 0))::decimal(10,4) as last_week_percentage,
	(coalesce(sum(case when (tm.full_resolution_time_in_minutes_calendar/60)<48 then 1 else 0 end)
	filter (
			where tm.full_resolution_time_in_minutes_calendar > 0  and t.status in ('closed', 'solved')
			and date_part('year', t.created_at) = date_part('year', (current_date - interval '1 month')::date)
  		and date_part('month', t.created_at) = date_part('month', (current_date - interval '1 month')::date)
  		and date_part('day', t.created_at) < date_part('day', current_date)
		)
	over ()::decimal(10,4), 0)  / nullif(count(1)
	filter (
			where date_part('year', t.created_at) = date_part('year', (current_date - interval '1 month')::date)
  		and date_part('month', t.created_at) = date_part('month', (current_date - interval '1 month')::date)
  		and date_part('day', t.created_at) < date_part('day', current_date)
		)
	over (), 0))::decimal(10,4) as last_month_percentage,
	(coalesce(sum(case when (tm.full_resolution_time_in_minutes_calendar/60)<48 then 1 else 0 end)
	filter (
			where tm.full_resolution_time_in_minutes_calendar > 0  and t.status in ('closed', 'solved')
			and date_part('year', t.created_at) = date_part('year', (current_date - interval '12 month')::date)
  		and ((date_part('month', t.created_at) = date_part('month', (current_date - interval '12 month')::date)
  		      and date_part('day', t.created_at) < date_part('day', (current_date - interval '12 month')::date))
  		  or date_part('month', t.created_at) < date_part('month', (current_date - interval '12 month')::date)
  		  )
		)
	over ()::decimal(10,4), 0)  / nullif(count(1)
	filter (
			where date_part('year', t.created_at) = date_part('year', (current_date - interval '12 month')::date)
  		and ((date_part('month', t.created_at) = date_part('month', (current_date - interval '12 month')::date)
  		      and date_part('day', t.created_at) < date_part('day', (current_date - interval '12 month')::date))
  		  or date_part('month', t.created_at) < date_part('month', (current_date - interval '12 month')::date)
  		  )
		)
	over (), 0))::decimal(10,4) as last_year_percentage
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
and t.created_at >= '2017-01-01'
order by t.created_at::date




