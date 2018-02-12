with all_dates_all_year as (
  select
		date_part('year', dp.dt_proposal_approved) as _year,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		count(distinct f.sk_user_visitor) as _count
	from fact_liquidity_property_scheduling f
	join dim_proposal dp
		on f.sk_proposal = dp.sk_proposal
			and dp.dt_proposal_approved >= '2017-01-01'
			and f.sk_proposal != -1
	group by date_part('year', dp.dt_proposal_approved)
	order by date_part('year', dp.dt_proposal_approved)
),
all_dates as (
	select distinct
    y._year,
    m._month,
    m._week,
    m._day,
    y.region,
    y.city,
    y._count as monthly_count
	from growth.approved_by_insurer_all_month m
	join all_dates_all_year y
  	on m._year = y._year
),
