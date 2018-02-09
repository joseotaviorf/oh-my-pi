with all_dates_all_month as (
	select
	 	date_part('year', dof.dt_approved) as _year,
	  date_part('month', dof.dt_approved) as _month,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(distinct dof.sk_offer) as _count
	from fact_liquidity_property_scheduling f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.dt_approved >= '2017-01-01'
			and f.sk_offer != -1
  group by date_part('year', dof.dt_approved), date_part('month', dof.dt_approved)
  order by date_part('year', dof.dt_approved), date_part('month', dof.dt_approved)
),
all_dates as (
	select distinct
    d._year,
    d._month,
    w._week,
    d._day,
    d.region,
    d.city,
    m._count as monthly_count
	from growth.offers_approved_all_day d
	join growth.offers_approved_all_week w
  	on d._year = w._year
    	and d._month = w._month
      and d._week = w._week
	join all_dates_all_month m
  	on d._year = m._year
    	and d._month = m._month
),
