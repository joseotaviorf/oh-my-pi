with all_dates as (
	select distinct
    date_part('year', dp.publication_date) as _year,
    date_part('month', dp.publication_date) as _month,
    date_part('week', dp.publication_date) as _week,
    date_part('day', dp.publication_date) as _day,
    coalesce(dr.long_region_name, '') as region,
    'QuintoAndar'::varchar as city,
    dense_rank() over (partition by coalesce(dr.long_region_name, ''),
                                    date_part('year', dp.publication_date),
    																date_part('month', dp.publication_date),
    																date_part('week', dp.publication_date),
    																date_part('day', dp.publication_date) order by dp.sk_property asc)
    	+ dense_rank() over (partition by coalesce(dr.long_region_name, ''),
    	                                  date_part('year', dp.publication_date),
    																		date_part('month', dp.publication_date),
    																		date_part('week', dp.publication_date),
    																		date_part('day', dp.publication_date) order by dp.sk_property desc)
			- 1 as daily_count,
    dense_rank() over (partition by coalesce(dr.long_region_name, ''),
                                    date_part('year', dp.publication_date),
    																date_part('week', dp.publication_date) order by dp.sk_property asc)
    	+ dense_rank() over (partition by coalesce(dr.long_region_name, ''),
    	                                  date_part('year', dp.publication_date),
    																		date_part('week', dp.publication_date) order by dp.sk_property desc)
			- 1 as weekly_count,
    dense_rank() over (partition by coalesce(dr.long_region_name, ''),
                                    date_part('year', dp.publication_date),
    																date_part('month', dp.publication_date) order by dp.sk_property asc)
    	+ dense_rank() over (partition by coalesce(dr.long_region_name, ''),
    	                                  date_part('year', dp.publication_date),
    																		date_part('month', dp.publication_date) order by dp.sk_property desc)
			- 1 as monthly_count,
    dense_rank() over (partition by coalesce(dr.long_region_name, ''),
                                    date_part('year', dp.publication_date) order by dp.sk_property asc)
    	+ dense_rank() over (partition by coalesce(dr.long_region_name, ''),
    	                                  date_part('year', dp.publication_date) order by dp.sk_property desc)
			- 1 as yearly_count
	from fact_supply_potential_listings f
	join dim_property dp
		on f.sk_property = dp.sk_property
		  and dp.publication_date >= '2017-01-01' and dp.publication_date < current_date
		  and f.sk_property != -1
	join dim_property dpr
		on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
	join dim_contacts_and_prospects dcap
		on f.sk_lead = dcap.lead_id
	where dcap.attribution_type = 'Landing Page Leads'
  order by coalesce(dr.long_region_name, ''), date_part('year', dp.publication_date), date_part('month', dp.publication_date), date_part('week', dp.publication_date), date_part('day', dp.publication_date)
),
all_dates_last_week as (
	select 1
),
all_dates_last_month as (
	select
    date_part('year', dp.publication_date) as _year,
    date_part('month', dp.publication_date) as _month,
    coalesce(dr.long_region_name, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct dp.sk_property) as monthly_count
	from fact_supply_potential_listings f
	join dim_property dp
		on f.sk_property = dp.sk_property
		  and dp.publication_date >= '2017-01-01' and dp.publication_date < current_date
		  and f.sk_property != -1
	join dim_property dpr
  	on f.sk_property = dpr.sk_property
	left join dim_region dr
		on dpr.regiao_id = dr.id
	join dim_contacts_and_prospects dcap
		on f.sk_lead = dcap.lead_id
	where date_part('year', dp.publication_date) = date_part('year', add_months(current_date, -1))
  		and date_part('month', dp.publication_date) = date_part('month', add_months(current_date, -1))
  		and date_part('day', dp.publication_date) < date_part('day', current_date)
  		and dcap.attribution_type = 'Landing Page Leads'
 	group by coalesce(dr.long_region_name, ''), date_part('year', dp.publication_date), date_part('month', dp.publication_date)
  order by coalesce(dr.long_region_name, ''), date_part('year', dp.publication_date), date_part('month', dp.publication_date)
),
all_dates_last_year as (
	select
		date_part('year', dp.publication_date) as _year,
    coalesce(dr.long_region_name, '') as region,
    'QuintoAndar'::varchar as city,
    count(distinct dp.sk_property) as yearly_count
  from fact_supply_potential_listings f
	join dim_property dp
		on f.sk_property = dp.sk_property
		  and dp.publication_date >= '2017-01-01' and dp.publication_date < current_date
		  and f.sk_property != -1
  join dim_property dpr
  	on f.sk_property = dpr.sk_property
  left join dim_region dr
  	on dpr.regiao_id = dr.id
  join dim_contacts_and_prospects dcap
		on f.sk_lead = dcap.lead_id
  where date_part('year', dp.publication_date) = date_part('year', add_months(current_date, -12))
  		and ((date_part('month', dp.publication_date) = date_part('month', add_months(current_date, -12))
  		      and date_part('day', dp.publication_date) < date_part('day', add_months(current_date, -12)))
  		  or date_part('month', dp.publication_date) < date_part('month', add_months(current_date, -12))
  		  )
  		and dcap.attribution_type = 'Landing Page Leads'
	group by coalesce(dr.long_region_name, ''), date_part('year', dp.publication_date)
	order by coalesce(dr.long_region_name, ''), date_part('year', dp.publication_date)
),
