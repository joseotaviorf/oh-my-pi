with all_dates_all_month as (
	select
	 	date_part('year', dd."date") as _year,
	  date_part('month', dd."date") as _month,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(distinct(f.sk_contract)) as _count
	from fact_liquidity_property_scheduling f
	left join dim_contract dc
		on f.sk_contract = dc.sk_contract
	right join dim_date dd
		on dc.dt_contract_start <= dd."date"
			and coalesce(dc.dt_contract_annulment, dc.dt_contract_intended_end) >= dd."date"
	where dd."date" <= current_date
		and dc.dt_contract_start <= current_date
		and dc.contract_status != 'Cancelado'
		and f.sk_contract_signed_date != -1
		and dd."date" >= '2017-01-01'
  group by date_part('year', dd."date"), date_part('month', dd."date")
  order by date_part('year', dd."date"), date_part('month', dd."date")
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
	from growth.ongoing_contracts_all_day d
	join growth.ongoing_contracts_all_week w
  	on d._year = w._year
    	and d._month = w._month
      and d._week = w._week
	join all_dates_all_month m
  	on d._year = m._year
    	and d._month = m._month
),
