with all_dates_city_week as (
	select
		date_part('year', dof.dt_approved) as _year,
		date_part('week', dof.dt_approved) as _week,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(distinct f.sk_user_visitor) as _count
	from fact_liquidity_property_scheduling f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.status = 'Aprovada'
			and dof.dt_approved >= '2017-01-01'
			and f.sk_offer != -1
  join dim_property dpr
    on f.sk_property = dpr.sk_property
  left join dim_region dr
    on dpr.regiao_id = dr.id
	group by coalesce(dr.city_name, ''), date_part('year', dof.dt_approved), date_part('week', dof.dt_approved)
	order by coalesce(dr.city_name, ''), date_part('year', dof.dt_approved), date_part('week', dof.dt_approved)
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
	from all_dates_city_week w
	join growth.offerers_approved_city_day d
  	on d._year = w._year
      and d._week = w._week
      and d.city = w.city
      and d.region = w.region
),
