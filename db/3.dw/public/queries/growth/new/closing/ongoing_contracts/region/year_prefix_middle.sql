all_dates_last_year as (
	select
		date_part('year', dd."date") as _year,
    coalesce(dr.long_region_name, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct(f.sk_contract)) as _count
	from fact_liquidity_property_scheduling f
	left join dim_contract dc
		on f.sk_contract = dc.sk_contract
	right join dim_date dd
		on dc.dt_contract_start <= dd."date"
			and coalesce(dc.dt_contract_annulment, dc.dt_contract_intended_end) >= dd."date"
  join dim_property dpr
  	on f.sk_property = dpr.sk_property
  left join dim_region dr
  	on dpr.regiao_id = dr.id
  join partial_calc pc
  	on date_part('year', dd."date") = date_part('year', add_months(current_date, -12))
  		and date_part('month', dd."date") = date_part('month', add_months(current_date, -12))
  		and date_part('day', dd."date") <= date_part('day', add_months(current_date, -12))
	where dd."date" <= current_date
		and dc.dt_contract_start <= current_date
		and dc.contract_status != 'Cancelado'
		and f.sk_contract_signed_date != -1
		and dd."date" >= '2017-01-01'
	group by coalesce(dr.long_region_name, ''), date_part('year', dd."date")
	order by coalesce(dr.long_region_name, ''), date_part('year', dd."date")
),
