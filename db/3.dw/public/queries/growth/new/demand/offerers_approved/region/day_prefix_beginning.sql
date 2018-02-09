with all_dates as (
	select
    date_part('year', dof.dt_approved) as _year,
    date_part('month', dof.dt_approved) as _month,
    date_part('week', dof.dt_approved) as _week,
    date_part('day', dof.dt_approved) as _day,
    coalesce(dr.long_region_name, '') as region,
    'QuintoAndar'::varchar as city,
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
  group by coalesce(dr.long_region_name, ''), date_part('year', dof.dt_approved), date_part('month', dof.dt_approved), date_part('week', dof.dt_approved), date_part('day', dof.dt_approved)
  order by coalesce(dr.long_region_name, ''), date_part('year', dof.dt_approved), date_part('month', dof.dt_approved), date_part('week', dof.dt_approved), date_part('day', dof.dt_approved)
),
