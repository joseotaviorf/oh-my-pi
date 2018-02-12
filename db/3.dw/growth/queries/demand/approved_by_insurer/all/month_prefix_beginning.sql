with all_dates_all_month as (
  select
		date_part('year', dp.dt_proposal_approved) as _year,
		date_part('month', dp.dt_proposal_approved) as _month,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		count(distinct f.sk_user_visitor) as _count
	from fact_liquidity_property_scheduling f
	join dim_proposal dp
		on f.sk_proposal = dp.sk_proposal
			and dp.dt_proposal_approved >= '2017-01-01'
			and f.sk_proposal != -1
	group by date_part('year', dp.dt_proposal_approved), date_part('month', dp.dt_proposal_approved)
	order by date_part('year', dp.dt_proposal_approved), date_part('month', dp.dt_proposal_approved)
),
all_dates as (
	select distinct
    m._year,
    m._month,
    w._week,
    w._day,
    m.region,
    m.city,
    m._count as monthly_count
	from growth.approved_by_insurer_all_week w
	join all_dates_all_month m
  	on w._year = m._year
    	and w._month = m._month
),
