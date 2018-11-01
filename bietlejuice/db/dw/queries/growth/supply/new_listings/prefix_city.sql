with all_dates as (
	select distinct
    date_part('year', dp.publication_date) as _year,
    date_part('month', dp.publication_date) as _month,
    date_part('week', dp.publication_date) as _week,
    date_part('day', dp.publication_date) as _day,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', dp.publication_date),
    																date_part('month', dp.publication_date),
    																date_part('week', dp.publication_date),
    																date_part('day', dp.publication_date) order by dp.sk_house_listing asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', dp.publication_date),
    																		date_part('month', dp.publication_date),
    																		date_part('week', dp.publication_date),
    																		date_part('day', dp.publication_date) order by dp.sk_house_listing desc)
			- 1 as daily_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', dp.publication_date),
    																date_part('week', dp.publication_date) order by dp.sk_house_listing asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', dp.publication_date),
    																		date_part('week', dp.publication_date) order by dp.sk_house_listing desc)
			- 1 as weekly_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', dp.publication_date),
    																date_part('month', dp.publication_date) order by dp.sk_house_listing asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', dp.publication_date),
    																		date_part('month', dp.publication_date) order by dp.sk_house_listing desc)
			- 1 as monthly_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', dp.publication_date) order by dp.sk_house_listing asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', dp.publication_date) order by dp.sk_house_listing desc)
			- 1 as yearly_count
	from fact_supply f
	join dim_house_listing dp
		on f.sk_property = dp.sk_house_listing
		  and dp.publication_date >= '2017-01-01' and dp.publication_date < current_date
		  and f.sk_property != -1
	join dim_house_listing dpr
		on f.sk_property = dpr.sk_house_listing
	left join dim_region dr
		on dpr.regiao_id = dr.id
  order by coalesce(dr.city_name, ''), date_part('year', dp.publication_date), date_part('month', dp.publication_date), date_part('week', dp.publication_date), date_part('day', dp.publication_date)
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
    date_part('year', dp.publication_date) as _year,
    date_part('month', dp.publication_date) as _month,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(distinct dp.sk_house_listing) as monthly_count
	from fact_supply f
	join dim_house_listing dp
		on f.sk_property = dp.sk_house_listing
		  and dp.publication_date >= '2017-01-01' and dp.publication_date < current_date
		  and f.sk_property != -1
	join dim_house_listing dpr
  	on f.sk_property = dpr.sk_house_listing
	left join dim_region dr
		on dpr.regiao_id = dr.id
	where date_part('year', dp.publication_date) = date_part('year', add_months(current_date, -1))
  		and date_part('month', dp.publication_date) = date_part('month', add_months(current_date, -1))
  		and date_part('day', dp.publication_date) < date_part('day', current_date)
 	group by coalesce(dr.city_name, ''), date_part('year', dp.publication_date), date_part('month', dp.publication_date)
  order by coalesce(dr.city_name, ''), date_part('year', dp.publication_date), date_part('month', dp.publication_date)
),
all_dates_last_year as (
	select
		date_part('year', dp.publication_date) as _year,
		'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(distinct dp.sk_house_listing) as yearly_count
  from fact_supply f
	join dim_house_listing dp
		on f.sk_property = dp.sk_house_listing
		  and dp.publication_date >= '2017-01-01' and dp.publication_date < current_date
		  and f.sk_property != -1
  join dim_house_listing dpr
  	on f.sk_property = dpr.sk_house_listing
  left join dim_region dr
  	on dpr.regiao_id = dr.id
  where date_part('year', dp.publication_date) = date_part('year', add_months(current_date, -12))
  		and ((date_part('month', dp.publication_date) = date_part('month', add_months(current_date, -12))
  		      and date_part('day', dp.publication_date) < date_part('day', add_months(current_date, -12)))
  		  or date_part('month', dp.publication_date) < date_part('month', add_months(current_date, -12))
  		  )
	group by coalesce(dr.city_name, ''), date_part('year', dp.publication_date)
	order by coalesce(dr.city_name, ''), date_part('year', dp.publication_date)
),
