with all_dates_all_week as (
	select
		date_part('year', dof.dt_first_sent) as _year,
		date_part('week', dof.dt_first_sent) as _week,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
	  count(distinct dof.sk_offer) as _count
	from fact_liquidity_property_scheduling f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.dt_first_sent >= '2017-01-01'
			and f.sk_offer != -1
	group by date_part('year', dof.dt_first_sent), date_part('week', dof.dt_first_sent)
	order by date_part('year', dof.dt_first_sent), date_part('week', dof.dt_first_sent)
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
	join growth.offers_submitted_all_day d
  	on d._year = w._year
      and d._week = w._week
),
