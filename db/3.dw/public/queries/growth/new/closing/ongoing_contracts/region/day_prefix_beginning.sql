with all_dates as (
	select
    date_part('year', dd."date") as _year,
    date_part('month', dd."date") as _month,
    date_part('week', dd."date") as _week,
    date_part('day', dd."date") as _day,
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
	where dd."date" <= current_date
		and dc.dt_contract_start <= current_date
		and dc.contract_status != 'Cancelado'
		and f.sk_contract_signed_date != -1
		and dd."date" >= '2017-01-01'
  group by coalesce(dr.long_region_name, ''), date_part('year', dd."date"), date_part('month', dd."date"), date_part('week', dd."date"), date_part('day', dd."date")
  order by coalesce(dr.long_region_name, ''), date_part('year', dd."date"), date_part('month', dd."date"), date_part('week', dd."date"), date_part('day', dd."date")
),
