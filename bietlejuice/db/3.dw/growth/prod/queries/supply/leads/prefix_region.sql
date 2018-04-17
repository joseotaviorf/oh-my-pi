with all_dates_prev as (
	select
    date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) as _year,
    date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) as _month,
    date_part('week', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) as _week,
    date_part('day', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) as _day,
    coalesce(dr.long_region_name, '') as region,
    'QuintoAndar'::varchar as city,
    rank() over (partition by coalesce(dr.long_region_name, ''),
                                    date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
    																date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
    																date_part('week', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
    																date_part('day', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) order by f.sk_lead asc)
    	+ rank() over (partition by coalesce(dr.long_region_name, ''),
    	                                  date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
    																		date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
    																		date_part('week', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
    																		date_part('day', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) order by f.sk_lead desc)
			- 1 as daily_count,
    rank() over (partition by coalesce(dr.long_region_name, ''),
                                    date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
    																date_part('week', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) order by f.sk_lead asc)
    	+ rank() over (partition by coalesce(dr.long_region_name, ''),
    	                                  date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
    																		date_part('week', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) order by f.sk_lead desc)
			- 1 as weekly_count,
    rank() over (partition by coalesce(dr.long_region_name, ''),
                                    date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
    																date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) order by f.sk_lead asc)
    	+ rank() over (partition by coalesce(dr.long_region_name, ''),
    	                                  date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')),
    																		date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) order by f.sk_lead desc)
			- 1 as monthly_count,
    rank() over (partition by coalesce(dr.long_region_name, ''),
                                    date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) order by f.sk_lead asc)
    	+ rank() over (partition by coalesce(dr.long_region_name, ''),
    	                                  date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) order by f.sk_lead desc)
			- 1 as yearly_count
	from fact_supply f
	join dim_property dpr
		on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
  where to_date(f.sk_lead_date::varchar, 'YYYYMMDD') >= '2017-01-01' and to_date(f.sk_lead_date::varchar, 'YYYYMMDD') < current_date
  order by coalesce(dr.long_region_name, ''), date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')), date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')), date_part('week', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')), date_part('day', to_date(f.sk_lead_date::varchar, 'YYYYMMDD'))
),
all_dates as (
  select distinct
    _year,
    _month,
    _week,
    _day,
    region,
    city,
    max(daily_count) over (partition by region, _year, _month, _week, _day) as daily_count,
    max(weekly_count) over (partition by region, _year, _week) as weekly_count,
    max(monthly_count) over (partition by region, _year, _month) as monthly_count,
    max(yearly_count) over (partition by region, _year) as yearly_count
  from all_dates_prev
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
    date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) as _year,
    date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) as _month,
    coalesce(dr.long_region_name, '') as region,
    'QuintoAndar'::varchar as city,
    count(to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) as monthly_count
	from fact_supply f
	join dim_property dpr
  	on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
	where date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) = date_part('year', add_months(current_date, -1))
  		and date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) = date_part('month', add_months(current_date, -1))
  		and date_part('day', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) < date_part('day', current_date)
 	group by coalesce(dr.long_region_name, ''), date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')), date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD'))
  order by coalesce(dr.long_region_name, ''), date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')), date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD'))
),
all_dates_last_year as (
	select
		date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) as _year,
    coalesce(dr.long_region_name, '') as region,
    'QuintoAndar'::varchar as city,
    count(to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) as yearly_count
  from fact_supply f
  join dim_property dpr
  	on f.sk_property = dpr.sk_property
  left join dim_region dr
  	on dpr.regiao_id = dr.id
  where date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) = date_part('year', add_months(current_date, -12))
  		and ((date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) = date_part('month', add_months(current_date, -12))
  		      and date_part('day', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) < date_part('day', add_months(current_date, -12)))
  		  or date_part('month', to_date(f.sk_lead_date::varchar, 'YYYYMMDD')) < date_part('month', add_months(current_date, -12))
  		  )
	group by coalesce(dr.long_region_name, ''), date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD'))
	order by coalesce(dr.long_region_name, ''), date_part('year', to_date(f.sk_lead_date::varchar, 'YYYYMMDD'))
),
