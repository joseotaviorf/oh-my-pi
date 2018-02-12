with all_dates_all_month as (
	select
	 	date_part('year', dp.dt_tenant_first_document_sent) as _year,
	  date_part('month', dp.dt_tenant_first_document_sent) as _month,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(distinct f.sk_user_visitor) as _count
	from fact_liquidity_property_scheduling f
	join dim_proposal dp
		on f.sk_proposal = dp.sk_proposal
			and dp.dt_tenant_first_document_sent >= '2017-01-01'
			and f.sk_proposal != -1
  group by date_part('year', dp.dt_tenant_first_document_sent), date_part('month', dp.dt_tenant_first_document_sent)
  order by date_part('year', dp.dt_tenant_first_document_sent), date_part('month', dp.dt_tenant_first_document_sent)
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
	from growth.offerers_sent_doc_all_day d
	join growth.offerers_sent_doc_all_week w
  	on d._year = w._year
    	and d._month = w._month
      and d._week = w._week
	join all_dates_all_month m
  	on d._year = m._year
    	and d._month = m._month
),
