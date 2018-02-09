all_dates_last_month as (
  select
		date_part('year', dp.dt_tenant_first_document_sent) as _year,
		date_part('month', dp.dt_tenant_first_document_sent) as _month,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		count(distinct dp.sk_proposal) as _count
	from fact_liquidity_property_scheduling f
	join dim_proposal dp
		on f.sk_proposal = dp.sk_proposal
			and dp.dt_tenant_first_document_sent >= '2017-01-01'
			and f.sk_proposal != -1
	join partial_calc pc
  	on date_part('year', dp.dt_tenant_first_document_sent) = date_part('year', add_months(current_date, -1))
  		and date_part('month', dp.dt_tenant_first_document_sent) = date_part('month', add_months(current_date, -1))
  		and date_part('day', dp.dt_tenant_first_document_sent) <= date_part('day', current_date)
  group by date_part('year', dp.dt_tenant_first_document_sent), date_part('month', dp.dt_tenant_first_document_sent)
	order by date_part('year', dp.dt_tenant_first_document_sent), date_part('month', dp.dt_tenant_first_document_sent)
),
