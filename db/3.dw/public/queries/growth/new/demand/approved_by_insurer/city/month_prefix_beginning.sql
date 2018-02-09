with all_dates_city_month as (
  select
		date_part('year', dp.dt_proposal_approved) as _year,
		date_part('month', dp.dt_proposal_approved) as _month,
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
	group by coalesce(dr.city_name, ''), date_part('year', dp.dt_proposal_approved), date_part('month', dp.dt_proposal_approved)
	order by coalesce(dr.city_name, ''), date_part('year', dp.dt_proposal_approved), date_part('month', dp.dt_proposal_approved)
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
	from growth.approved_by_insurer_all_day d
	join growth.approved_by_insurer_all_week w
  	on d._year = w._year
    	and d._month = w._month
      and d._week = w._week
      and d.city = w.city
      and d.region = w.region
	join all_dates_city_month m
  	on d._year = m._year
    	and d._month = m._month
    	and d.city = m.city
    	and d.region = m.region
),
