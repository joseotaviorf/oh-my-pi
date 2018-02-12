all_dates_last_month as (
   select
		date_part('year', dp.dt_proposal_approved) as _year,
		date_part('month', dp.dt_proposal_approved) as _month,
		coalesce(dr.long_region_name, '') as region,
    'QuintoAndar'::varchar as city,
		count(distinct f.sk_user_visitor) as _count
	from fact_liquidity_property_scheduling f
	join dim_proposal dp
		on f.sk_proposal = dp.sk_proposal
			and dp.dt_proposal_approved >= '2017-01-01'
			and f.sk_proposal != -1
  join dim_property dpr
		on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
	join partial_calc pc
  	on date_part('year', dp.dt_proposal_approved) = date_part('year', add_months(current_date, -1))
  		and date_part('month', dp.dt_proposal_approved) = date_part('month', add_months(current_date, -1))
  		and date_part('day', dp.dt_proposal_approved) <= date_part('day', current_date)
	group by coalesce(dr.long_region_name, ''), date_part('year', dp.dt_proposal_approved), date_part('month', dp.dt_proposal_approved)
	order by coalesce(dr.long_region_name, ''), date_part('year', dp.dt_proposal_approved), date_part('month', dp.dt_proposal_approved)
),
