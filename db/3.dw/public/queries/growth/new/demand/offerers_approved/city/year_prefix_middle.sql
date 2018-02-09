all_dates_last_year as (
	select
		date_part('year', dof.dt_approved) as _year,
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
  join partial_calc pc
  	on date_part('year', dof.dt_approved) = date_part('year', add_months(current_date, -12))
  		and date_part('month', dof.dt_approved) = date_part('month', add_months(current_date, -12))
  		and date_part('day', dof.dt_approved) <= date_part('day', add_months(current_date, -12))
	group by coalesce(dr.city_name, ''), date_part('year', dof.dt_approved)
	order by coalesce(dr.city_name, ''), date_part('year', dof.dt_approved)
),
