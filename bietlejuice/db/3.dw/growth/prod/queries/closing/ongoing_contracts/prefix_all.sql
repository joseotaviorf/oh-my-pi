with all_dates as (
  select distinct
    date_part('year', dd."date") as _year,
    date_part('month', dd."date") as _month,
    date_part('week', dd."date") as _week,
    date_part('day', dd."date") as _day,
    'QuintoAndar'::varchar as region,
    'QuintoAndar'::varchar as city,
    dense_rank() over (partition by date_part('year', dd."date"),
    																date_part('month', dd."date"),
    																date_part('week', dd."date"),
    																date_part('day', dd."date") order by f.sk_contract asc)
    	+ dense_rank() over (partition by date_part('year', dd."date"),
    																		date_part('month', dd."date"),
    																		date_part('week', dd."date"),
    																		date_part('day', dd."date") order by f.sk_contract desc)
			- 1 as daily_count,
    dense_rank() over (partition by date_part('year', dd."date"),
    																date_part('week', dd."date") order by f.sk_contract asc)
    	+ dense_rank() over (partition by date_part('year', dd."date"),
    																		date_part('week', dd."date") order by f.sk_contract desc)
			- 1 as weekly_count,
    dense_rank() over (partition by date_part('year', dd."date"),
    																date_part('month', dd."date") order by f.sk_contract asc)
    	+ dense_rank() over (partition by date_part('year', dd."date"),
    																		date_part('month', dd."date") order by f.sk_contract desc)
			- 1 as monthly_count,
    dense_rank() over (partition by date_part('year', dd."date") order by f.sk_contract asc)
    	+ dense_rank() over (partition by date_part('year', dd."date") order by f.sk_contract desc)
			- 1 as yearly_count
	from fact_demand f
	left join dim_contract dc
		on f.sk_contract = dc.sk_contract
	right join dim_date dd
		on dc.dt_contract_start <= dd."date"
			and coalesce(dc.dt_contract_annulment, dc.dt_contract_intended_end) >= dd."date"
	where dc.dt_contract_start < current_date
		and dc.contract_status != 'Cancelado'
		and f.sk_contract_signed_date != -1
		and dd."date" >= '2017-01-01' and dd."date" < current_date
  order by date_part('year', dd."date"), date_part('month', dd."date"), date_part('week', dd."date"), date_part('day', dd."date")
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
	 	date_part('year', dd."date") as _year,
	  date_part('month', dd."date") as _month,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(distinct f.sk_contract) as monthly_count
	from fact_demand f
	left join dim_contract dc
		on f.sk_contract = dc.sk_contract
	right join dim_date dd
		on dc.dt_contract_start <= dd."date"
			and coalesce(dc.dt_contract_annulment, dc.dt_contract_intended_end) >= dd."date"
  where dc.dt_contract_start < current_date
		and dc.contract_status != 'Cancelado'
		and f.sk_contract_signed_date != -1
		and dd."date" >= '2017-01-01' and dd."date" < current_date
		and date_part('year', dd."date") = date_part('year', add_months(current_date, -1))
  	and date_part('month', dd."date") = date_part('month', add_months(current_date, -1))
  	and date_part('day', dd."date") < date_part('day', current_date)
  group by date_part('year', dd."date"), date_part('month', dd."date")
  order by date_part('year', dd."date"), date_part('month', dd."date")
),
all_dates_last_year as (
	select
	 	date_part('year', dd."date") as _year,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(distinct f.sk_contract) as yearly_count
	from fact_demand f
	left join dim_contract dc
		on f.sk_contract = dc.sk_contract
	right join dim_date dd
		on dc.dt_contract_start <= dd."date"
			and coalesce(dc.dt_contract_annulment, dc.dt_contract_intended_end) >= dd."date"
	where dc.dt_contract_start < current_date
		and dc.contract_status != 'Cancelado'
		and f.sk_contract_signed_date != -1
		and dd."date" >= '2017-01-01' and dd."date" < current_date
	  and date_part('year', dd."date") = date_part('year', add_months(current_date, -12))
  		and ((date_part('month', dd."date") = date_part('month', add_months(current_date, -12))
  		      and date_part('day', dd."date") < date_part('day', add_months(current_date, -12)))
  		  or date_part('month', dd."date") < date_part('month', add_months(current_date, -12))
  		  )
  group by date_part('year', dd."date")
  order by date_part('year', dd."date")
),