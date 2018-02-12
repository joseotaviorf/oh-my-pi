with all_dates as (
  select
    date_part('year', dp.dt_tenant_first_document_sent) as _year,
    date_part('month', dp.dt_tenant_first_document_sent) as _month,
    date_part('week', dp.dt_tenant_first_document_sent) as _week,
    date_part('day', dp.dt_tenant_first_document_sent) as _day,
    'QuintoAndar'::varchar as region,
    'QuintoAndar'::varchar as city,
    count(distinct f.sk_user_visitor) as _count
	from fact_liquidity_property_scheduling f
	join dim_proposal dp
		on f.sk_proposal = dp.sk_proposal
			and dp.dt_tenant_first_document_sent >= '2017-01-01'
			and f.sk_proposal != -1
  group by date_part('year', dp.dt_tenant_first_document_sent), date_part('month', dp.dt_tenant_first_document_sent), date_part('week', dp.dt_tenant_first_document_sent), date_part('day', dp.dt_tenant_first_document_sent)
  order by date_part('year', dp.dt_tenant_first_document_sent), date_part('month', dp.dt_tenant_first_document_sent), date_part('week', dp.dt_tenant_first_document_sent), date_part('day', dp.dt_tenant_first_document_sent)
),
