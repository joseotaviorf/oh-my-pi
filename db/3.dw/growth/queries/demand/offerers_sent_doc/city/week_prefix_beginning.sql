with all_dates_city_week as (
	select
		date_part('year', dp.dt_tenant_first_document_sent) as _year,
		date_part('week', dp.dt_tenant_first_document_sent) as _week,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(distinct f.sk_user_visitor) as _count
	from fact_liquidity_property_scheduling f
	join dim_proposal dp
		on f.sk_proposal = dp.sk_proposal
			and dp.dt_tenant_first_document_sent >= '2017-01-01'
			and f.sk_proposal != -1
  join dim_property dpr
    on f.sk_property = dpr.sk_property
  left join dim_region dr
    on dpr.regiao_id = dr.id
	group by coalesce(dr.city_name, ''), date_part('year', dp.dt_tenant_first_document_sent), date_part('week', dp.dt_tenant_first_document_sent)
	order by coalesce(dr.city_name, ''), date_part('year', dp.dt_tenant_first_document_sent), date_part('week', dp.dt_tenant_first_document_sent)
),
all_dates as (
	select
    w._year,
    d._month,
    w._week,
    d._day,
    w.region,
    w.city,
    w._count as weekly_count
	from all_dates_city_week w
	join growth.offerers_sent_doc_city_day d
  	on d._year = w._year
      and d._week = w._week
      and d.city = w.city
      and d.region = w.region
),
