with all_dates as (
	select distinct
    date_part('year', dof.dt_approved) as _year,
    date_part('month', dof.dt_approved) as _month,
    date_part('week', dof.dt_approved) as _week,
    date_part('day', dof.dt_approved) as _day,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', dof.dt_approved),
    																date_part('month', dof.dt_approved),
    																date_part('week', dof.dt_approved),
    																date_part('day', dof.dt_approved) order by f.sk_user_visitor asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', dof.dt_approved),
    																		date_part('month', dof.dt_approved),
    																		date_part('week', dof.dt_approved),
    																		date_part('day', dof.dt_approved) order by f.sk_user_visitor desc)
			- 1 as daily_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', dof.dt_approved),
    																date_part('week', dof.dt_approved) order by f.sk_user_visitor asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', dof.dt_approved),
    																		date_part('week', dof.dt_approved) order by f.sk_user_visitor desc)
			- 1 as weekly_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', dof.dt_approved),
    																date_part('month', dof.dt_approved) order by f.sk_user_visitor asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', dof.dt_approved),
    																		date_part('month', dof.dt_approved) order by f.sk_user_visitor desc)
			- 1 as monthly_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', dof.dt_approved) order by f.sk_user_visitor asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', dof.dt_approved) order by f.sk_user_visitor desc)
			- 1 as yearly_count
	from fact_liquidity_property_scheduling f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.status = 'Aprovada'
			and dof.dt_approved >= '2017-01-01' and dof.dt_approved < current_date
			and f.sk_offer != -1
	join dim_property dpr
		on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
  order by coalesce(dr.city_name, ''), date_part('year', dof.dt_approved), date_part('month', dof.dt_approved), date_part('week', dof.dt_approved), date_part('day', dof.dt_approved)
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
    date_part('year', dof.dt_approved) as _year,
    date_part('month', dof.dt_approved) as _month,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(distinct f.sk_user_visitor) as monthly_count
	from fact_liquidity_property_scheduling f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.status = 'Aprovada'
			and dof.dt_approved >= '2017-01-01' and dof.dt_approved < current_date
			and f.sk_offer != -1
	join dim_property dpr
  	on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
	where date_part('year', dof.dt_approved) = date_part('year', add_months(current_date, -1))
  		and date_part('month', dof.dt_approved) = date_part('month', add_months(current_date, -1))
  		and date_part('day', dof.dt_approved) < date_part('day', current_date)
 	group by coalesce(dr.city_name, ''), date_part('year', dof.dt_approved), date_part('month', dof.dt_approved)
  order by coalesce(dr.city_name, ''), date_part('year', dof.dt_approved), date_part('month', dof.dt_approved)
),
all_dates_last_year as (
	select
		date_part('year', dof.dt_approved) as _year,
		'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(distinct f.sk_user_visitor) as yearly_count
  from fact_liquidity_property_scheduling f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.status = 'Aprovada'
			and dof.dt_approved >= '2017-01-01' and dof.dt_approved < current_date
			and f.sk_offer != -1
  join dim_property dpr
  	on f.sk_property = dpr.sk_property
  left join dim_region dr
  	on dpr.regiao_id = dr.id
	where date_part('year', dof.dt_approved) = date_part('year', add_months(current_date, -12))
  		and ((date_part('month', dof.dt_approved) = date_part('month', add_months(current_date, -12))
  		      and date_part('day', dof.dt_approved) < date_part('day', add_months(current_date, -12)))
  		  or date_part('month', dof.dt_approved) < date_part('month', add_months(current_date, -12))
  		  )
	group by coalesce(dr.city_name, ''), date_part('year', dof.dt_approved)
	order by coalesce(dr.city_name, ''), date_part('year', dof.dt_approved)
),
