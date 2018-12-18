with all_dates as (
	select distinct
    date_part('year', dhl.ts_publication) as _year,
    date_part('month', dhl.ts_publication) as _month,
    date_part('week', dhl.ts_publication) as _week,
    date_part('day', dhl.ts_publication) as _day,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', dhl.ts_publication),
    																date_part('month', dhl.ts_publication),
    																date_part('week', dhl.ts_publication),
    																date_part('day', dhl.ts_publication) order by dhl.sk_house_listing asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', dhl.ts_publication),
    																		date_part('month', dhl.ts_publication),
    																		date_part('week', dhl.ts_publication),
    																		date_part('day', dhl.ts_publication) order by dhl.sk_house_listing desc)
			- 1 as daily_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', dhl.ts_publication),
    																date_part('week', dhl.ts_publication) order by dhl.sk_house_listing asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', dhl.ts_publication),
    																		date_part('week', dhl.ts_publication) order by dhl.sk_house_listing desc)
			- 1 as weekly_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', dhl.ts_publication),
    																date_part('month', dhl.ts_publication) order by dhl.sk_house_listing asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', dhl.ts_publication),
    																		date_part('month', dhl.ts_publication) order by dhl.sk_house_listing desc)
			- 1 as monthly_count,
    dense_rank() over (partition by coalesce(dr.city_name, ''),
                                    date_part('year', dhl.ts_publication) order by dhl.sk_house_listing asc)
    	+ dense_rank() over (partition by coalesce(dr.city_name, ''),
    	                                  date_part('year', dhl.ts_publication) order by dhl.sk_house_listing desc)
			- 1 as yearly_count
	from fact_house_listing_flows f
	join dim_house_listing dhl
		on f.sk_house_listing = dhl.sk_house_listing
		  and dhl.ts_publication >= '2017-01-01' and dhl.ts_publication < current_date
		  and f.sk_house_listing != -1
	join fact_house_listings fhl
	  on fhl.sk_house_listing = dhl.sk_house_listing
	left join dim_region dr
		on fhl.sk_region = dr.sk_region
  order by coalesce(dr.city_name, ''), date_part('year', dhl.ts_publication), date_part('month', dhl.ts_publication), date_part('week', dhl.ts_publication), date_part('day', dhl.ts_publication)
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
    date_part('year', dhl.ts_publication) as _year,
    date_part('month', dhl.ts_publication) as _month,
    'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(distinct dhl.sk_house_listing) as monthly_count
	from fact_house_listing_flows f
	join dim_house_listing dhl
		on f.sk_house_listing = dhl.sk_house_listing
		  and dhl.ts_publication >= '2017-01-01' and dhl.ts_publication < current_date
		  and f.sk_house_listing != -1
	join fact_house_listings fhl
	  on fhl.sk_house_listing = dhl.sk_house_listing
	left join dim_region dr
		on fhl.sk_region = dr.sk_region
	where date_part('year', dhl.ts_publication) = date_part('year', add_months(current_date, -1))
  		and date_part('month', dhl.ts_publication) = date_part('month', add_months(current_date, -1))
  		and date_part('day', dhl.ts_publication) < date_part('day', current_date)
 	group by coalesce(dr.city_name, ''), date_part('year', dhl.ts_publication), date_part('month', dhl.ts_publication)
  order by coalesce(dr.city_name, ''), date_part('year', dhl.ts_publication), date_part('month', dhl.ts_publication)
),
all_dates_last_year as (
	select
		date_part('year', dhl.ts_publication) as _year,
		'QuintoAndar'::varchar as region,
    coalesce(dr.city_name, '') as city,
    count(distinct dhl.sk_house_listing) as yearly_count
  from fact_house_listing_flows f
	join dim_house_listing dhl
		on f.sk_house_listing = dhl.sk_house_listing
		  and dhl.ts_publication >= '2017-01-01' and dhl.ts_publication < current_date
		  and f.sk_house_listing != -1
  join fact_house_listings fhl
	  on fhl.sk_house_listing = dhl.sk_house_listing
	left join dim_region dr
		on fhl.sk_region = dr.sk_region
  where date_part('year', dhl.ts_publication) = date_part('year', add_months(current_date, -12))
  		and ((date_part('month', dhl.ts_publication) = date_part('month', add_months(current_date, -12))
  		      and date_part('day', dhl.ts_publication) < date_part('day', add_months(current_date, -12)))
  		  or date_part('month', dhl.ts_publication) < date_part('month', add_months(current_date, -12))
  		  )
	group by coalesce(dr.city_name, ''), date_part('year', dhl.ts_publication)
	order by coalesce(dr.city_name, ''), date_part('year', dhl.ts_publication)
),
