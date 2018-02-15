all_dates_last_year as (
	select
	 	date_part('year', dp.dt_tenant_first_document_sent) as _year,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(distinct dp.sk_proposal) as _count
	from fact_liquidity_property_scheduling f
	join dim_booking db
  	on f.sk_booking = db.sk_booking
			and f.sk_booking != -1
  		and dp.dt_tenant_first_document_sent >= '2017-01-01'
  join partial_calc pc
  	on date_part('year', dp.dt_tenant_first_document_sent) = date_part('year', add_months(current_date, -12))
  		and date_part('month', dp.dt_tenant_first_document_sent) = date_part('month', add_months(current_date, -12))
  		and date_part('day', dp.dt_tenant_first_document_sent) <= date_part('day', add_months(current_date, -12))
  group by date_part('year', dp.dt_tenant_first_document_sent)
  order by date_part('year', dp.dt_tenant_first_document_sent)
),
