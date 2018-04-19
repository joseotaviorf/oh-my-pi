with all_dates as (
  select distinct
    date_part('year', dof.dt_first_sent) as _year,
    date_part('month', dof.dt_first_sent) as _month,
    date_part('week', dof.dt_first_sent) as _week,
    date_part('day', dof.dt_first_sent) as _day,
    'QuintoAndar'::varchar as region,
    'QuintoAndar'::varchar as city,
    dense_rank() over (partition by date_part('year', dof.dt_first_sent),
    																date_part('month', dof.dt_first_sent),
    																date_part('week', dof.dt_first_sent),
    																date_part('day', dof.dt_first_sent) order by dof.sk_offer asc)
    	+ dense_rank() over (partition by date_part('year', dof.dt_first_sent),
    																		date_part('month', dof.dt_first_sent),
    																		date_part('week', dof.dt_first_sent),
    																		date_part('day', dof.dt_first_sent) order by dof.sk_offer desc)
			- 1 as daily_count,
    dense_rank() over (partition by date_part('year', dof.dt_first_sent),
    																date_part('week', dof.dt_first_sent) order by dof.sk_offer asc)
    	+ dense_rank() over (partition by date_part('year', dof.dt_first_sent),
    																		date_part('week', dof.dt_first_sent) order by dof.sk_offer desc)
			- 1 as weekly_count,
    dense_rank() over (partition by date_part('year', dof.dt_first_sent),
    																date_part('month', dof.dt_first_sent) order by dof.sk_offer asc)
    	+ dense_rank() over (partition by date_part('year', dof.dt_first_sent),
    																		date_part('month', dof.dt_first_sent) order by dof.sk_offer desc)
			- 1 as monthly_count,
    dense_rank() over (partition by date_part('year', dof.dt_first_sent) order by dof.sk_offer asc)
    	+ dense_rank() over (partition by date_part('year', dof.dt_first_sent) order by dof.sk_offer desc)
			- 1 as yearly_count
	from fact_demand f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.dt_first_sent >= '2017-01-01' and dof.dt_first_sent < current_date
			and f.sk_offer != -1
  order by date_part('year', dof.dt_first_sent), date_part('month', dof.dt_first_sent), date_part('week', dof.dt_first_sent), date_part('day', dof.dt_first_sent)
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
	 	date_part('year', dof.dt_first_sent) as _year,
	  date_part('month', dof.dt_first_sent) as _month,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(distinct dof.sk_offer) as monthly_count
	from fact_demand f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.dt_first_sent >= '2017-01-01' and dof.dt_first_sent < current_date
			and f.sk_offer != -1
  where date_part('year', dof.dt_first_sent) = date_part('year', add_months(current_date, -1))
  		and date_part('month', dof.dt_first_sent) = date_part('month', add_months(current_date, -1))
  		and date_part('day', dof.dt_first_sent) < date_part('day', current_date)
  group by date_part('year', dof.dt_first_sent), date_part('month', dof.dt_first_sent)
  order by date_part('year', dof.dt_first_sent), date_part('month', dof.dt_first_sent)
),
all_dates_last_year as (
	select
	 	date_part('year', dof.dt_first_sent) as _year,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(distinct dof.sk_offer) as yearly_count
	from fact_demand f
	join dim_offer dof
		on f.sk_offer = dof.sk_offer
			and dof.dt_first_sent >= '2017-01-01' and dof.dt_first_sent < current_date
			and f.sk_offer != -1
	where date_part('year', dof.dt_first_sent) = date_part('year', add_months(current_date, -12))
  		and ((date_part('month', dof.dt_first_sent) = date_part('month', add_months(current_date, -12))
  		      and date_part('day', dof.dt_first_sent) < date_part('day', add_months(current_date, -12)))
  		  or date_part('month', dof.dt_first_sent) < date_part('month', add_months(current_date, -12))
  		  )
  group by date_part('year', dof.dt_first_sent)
  order by date_part('year', dof.dt_first_sent)
),