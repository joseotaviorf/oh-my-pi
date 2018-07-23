with all_dates as (
  select distinct
    date_part('year', dl.criado_em) as _year,
    date_part('month', dl.criado_em) as _month,
    date_part('week', dl.criado_em) as _week,
    date_part('day', dl.criado_em) as _day,
    'QuintoAndar'::varchar as region,
    'QuintoAndar'::varchar as city,
    dense_rank() over (partition by date_part('year', dl.criado_em),
    																date_part('month', dl.criado_em),
    																date_part('week', dl.criado_em),
    																date_part('day', dl.criado_em) order by dp.sk_property asc)
    	+ dense_rank() over (partition by date_part('year', dl.criado_em),
    																		date_part('month', dl.criado_em),
    																		date_part('week', dl.criado_em),
    																		date_part('day', dl.criado_em) order by dp.sk_property desc)
			- 1 as daily_count,
    dense_rank() over (partition by date_part('year', dl.criado_em),
    																date_part('week', dl.criado_em) order by dp.sk_property asc)
    	+ dense_rank() over (partition by date_part('year', dl.criado_em),
    																		date_part('week', dl.criado_em) order by dp.sk_property desc)
			- 1 as weekly_count,
    dense_rank() over (partition by date_part('year', dl.criado_em),
    																date_part('month', dl.criado_em) order by dp.sk_property asc)
    	+ dense_rank() over (partition by date_part('year', dl.criado_em),
    																		date_part('month', dl.criado_em) order by dp.sk_property desc)
			- 1 as monthly_count,
    dense_rank() over (partition by date_part('year', dl.criado_em) order by dp.sk_property asc)
    	+ dense_rank() over (partition by date_part('year', dl.criado_em) order by dp.sk_property desc)
			- 1 as yearly_count
	from fact_supply f
	join dim_property dp
		on f.sk_property = dp.sk_property
		  and dp.publication_date >= '2017-01-01' and dp.publication_date < current_date
		  and f.sk_property != -1
	join dim_lead dl
		on f.sk_lead = dl.sk_lead
	where f.acquisition_channel = 'Landing Page Leads' and coalesce(f.mkt_medium, '') <> 'Affiliate Networks'
  order by date_part('year', dl.criado_em), date_part('month', dl.criado_em), date_part('week', dl.criado_em), date_part('day', dl.criado_em)
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
	 	date_part('year', dl.criado_em) as _year,
	  date_part('month', dl.criado_em) as _month,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(distinct dp.sk_property) as monthly_count
	from fact_supply f
	join dim_property dp
		on f.sk_property = dp.sk_property
		  and f.sk_property != -1
	join dim_lead dl
		on f.sk_lead = dl.sk_lead
		  and dl.criado_em >= '2017-01-01' and dl.criado_em < current_date
  where date_part('year', dl.criado_em) = date_part('year', add_months(current_date, -1))
  		and date_part('month', dl.criado_em) = date_part('month', add_months(current_date, -1))
  		and date_part('day', dl.criado_em) < date_part('day', current_date)
  		and f.acquisition_channel = 'Landing Page Leads'
  group by date_part('year', dl.criado_em), date_part('month', dl.criado_em)
  order by date_part('year', dl.criado_em), date_part('month', dl.criado_em)
),
all_dates_last_year as (
	select
	 	date_part('year', dl.criado_em) as _year,
	  'QuintoAndar'::varchar as region,
	  'QuintoAndar'::varchar as city,
  	count(distinct dp.sk_property) as yearly_count
	from fact_supply f
	join dim_property dp
		on f.sk_property = dp.sk_property
		  and f.sk_property != -1
	join dim_lead dl
		on f.sk_lead = dl.sk_lead
		  and dl.criado_em >= '2017-01-01' and dl.criado_em < current_date
  where date_part('year', dl.criado_em) = date_part('year', add_months(current_date, -12))
  		and ((date_part('month', dl.criado_em) = date_part('month', add_months(current_date, -12))
  		      and date_part('day', dl.criado_em) < date_part('day', add_months(current_date, -12)))
  		  or date_part('month', dl.criado_em) < date_part('month', add_months(current_date, -12))
  		  )
  		and f.acquisition_channel = 'Landing Page Leads' and coalesce(f.mkt_medium, '') <> 'Affiliate Networks'
  group by date_part('year', dl.criado_em)
  order by date_part('year', dl.criado_em)
),