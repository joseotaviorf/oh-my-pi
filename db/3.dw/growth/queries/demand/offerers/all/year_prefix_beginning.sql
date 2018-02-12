with all_dates_all_year as (
	select
		date_part('year', dof.dt_first_sent) as _year,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		count(distinct f.sk_user_visitor) as _count
	from fact_liquidity_property_scheduling f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.offer_submitted is true
			and dof.dt_first_sent >= '2017-01-01'
			and f.sk_offer != - 1
	group by date_part('year', dof.dt_first_sent)
	order by date_part('year', dof.dt_first_sent)
),
all_dates as (
	select distinct
    d._year,
    d._month,
    w._week,
    d._day,
    d.region,
    d.city,
    y._count as yearly_count
	from growth.offerers_all_day d
	join growth.offerers_all_week w
  	on d._year = w._year
    	and d._month = w._month
      and d._week = w._week
	join all_dates_all_year y
  	on d._year = y._year
),
