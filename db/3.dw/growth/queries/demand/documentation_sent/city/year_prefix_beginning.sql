with all_dates_city_year as (
  select
		date_part('year', dp.dt_tenant_first_document_sent) as _year,
		'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
		count(distinct dp.sk_proposal) as _count
	from fact_liquidity_property_scheduling f
	join dim_proposal dp
		on f.sk_proposal = dp.sk_proposal
			and dp.dt_tenant_first_document_sent >= '2017-01-01'
			and f.sk_proposal != -1
	join dim_property dpr
  	on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
	group by coalesce(dr.city_name, ''), date_part('year', dp.dt_tenant_first_document_sent)
	order by coalesce(dr.city_name, ''), date_part('year', dp.dt_tenant_first_document_sent)
),
all_dates as (
	select distinct
    y._year,
    d._month,
    w._week,
    d._day,
    y.region,
    y.city,
    y._count as yearly_count
	from growth.documentation_sent_city_day d
	join growth.documentation_sent_city_week w
  	on d.city = w.city
  		and d.region = w.region
  		and d._year = w._year
    	and d._month = w._month
      and d._week = w._week
	join all_dates_city_year y
  	on d.city = y.city
  		and d.region = y.region
  		and d._year = y._year
),
