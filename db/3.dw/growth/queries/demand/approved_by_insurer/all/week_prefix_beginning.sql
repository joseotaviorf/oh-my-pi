with all_dates_all_week as (
  select
		date_part('year', dp.dt_proposal_approved) as _year,
		date_part('week', dp.dt_proposal_approved) as _week,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		count(distinct f.sk_user_visitor) as _count
	from fact_liquidity_property_scheduling f
	join dim_proposal dp
		on f.sk_proposal = dp.sk_proposal
			and dp.dt_proposal_approved >= '2017-01-01'
			and f.sk_proposal != -1
	group by date_part('year', dp.dt_proposal_approved), date_part('week', dp.dt_proposal_approved)
	order by date_part('year', dp.dt_proposal_approved), date_part('week', dp.dt_proposal_approved)
),
all_dates as (
	select
    w._year,
    d._month,
    w._week,
    d._day,
    w.region,
    w.city,
    w._count as weekly_count
	from all_dates_all_week w
	join growth.approved_by_insurer_all_day d
  	on d._year = w._year
      and d._week = w._week
),
