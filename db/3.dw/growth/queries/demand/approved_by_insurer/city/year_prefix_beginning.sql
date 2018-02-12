with all_dates_city_year as (
  select
		date_part('year', dp.dt_proposal_approved) as _year,
		'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
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
	group by coalesce(dr.city_name, ''), date_part('year', dp.dt_proposal_approved)
	order by coalesce(dr.city_name, ''), date_part('year', dp.dt_proposal_approved)
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
	from growth.tenant_prospects_city_day d
	join growth.tenant_prospects_city_week w
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
