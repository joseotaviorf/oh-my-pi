with all_dates_city_month as (
	select
    date_part('year', dof.dt_first_sent) as _year,
    date_part('month', dof.dt_first_sent) as _month,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(distinct f.sk_user_visitor) as _count
	from fact_liquidity_property_scheduling f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.offer_submitted is true
			and dof.dt_first_sent >= '2017-01-01'
			and f.sk_offer != - 1
	join dim_property dpr
  	on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
 	group by coalesce(dr.city_name, ''), date_part('year', dof.dt_first_sent), date_part('month', dof.dt_first_sent)
  order by coalesce(dr.city_name, ''), date_part('year', dof.dt_first_sent), date_part('month', dof.dt_first_sent)
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
	from growth.offerers_all_day d
	join growth.offerers_all_week w
  	on d._year = w._year
    	and d._month = w._month
      and d._week = w._week
      and d.city = w.city
      and d.region = w.region
	join all_dates_city_month m
  	on d._year = m._year
    	and d._month = m._month
    	and d.city = m.city
    	and d.region = m.region
),
