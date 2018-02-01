drop table if exists growth.prospects;
create table growth.prospects as

-- Get each date part from the corresponding column and make two concatenations: year+month+week and year+month
-- The concatenation is necessary because Redshift doesn't apply the 'over partition' the same way as Postgres, so
-- the data gets all shuffled up.
-- In addition, two CTE are needed so double counting doesn't happen if all regions are summed up.
with all_dates_all as (
  select
		date_part('year', f.dt_lead_and_prospect) as _year,
		date_part('month', f.dt_lead_and_prospect) as _month,
		date_part('week', f.dt_lead_and_prospect) as _week,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		(date_part('year', f.dt_lead_and_prospect)::varchar
			|| lpad(date_part('month', f.dt_lead_and_prospect)::varchar, 2, '0')
			|| lpad(date_part('week', f.dt_lead_and_prospect)::varchar, 2, '0'))::int  as concat_all,
		(date_part('year', f.dt_lead_and_prospect)::varchar
			|| lpad(date_part('month', f.dt_lead_and_prospect)::varchar, 2, '0'))::int  as concat_month,
		count(f.dt_lead_and_prospect) as _count
	from fact_supply_potential_listings f
	join dim_contacts_and_prospects cp
	  on f.cap_id = cp.sk_cap_id
			and ((cp.status != 'Descartado'
	  		and cp.automatically_discarded is not true
	  		and cp.self_service is false)
	  	or cp.self_service is true)
	group by date_part('year', f.dt_lead_and_prospect), date_part('month', f.dt_lead_and_prospect), date_part('week', f.dt_lead_and_prospect)
	order by date_part('year', f.dt_lead_and_prospect), date_part('month', f.dt_lead_and_prospect), date_part('week', f.dt_lead_and_prospect)
),
all_dates_region as (
	select
		date_part('year', f.dt_lead_and_prospect) as _year,
		date_part('month', f.dt_lead_and_prospect) as _month,
		date_part('week', f.dt_lead_and_prospect) as _week,
		r.long_region_name as region,
		r.city_name as city,
		(date_part('year', f.dt_lead_and_prospect)::varchar
			|| lpad(date_part('month', f.dt_lead_and_prospect)::varchar, 2, '0')
			|| lpad(date_part('week', f.dt_lead_and_prospect)::varchar, 2, '0'))::int  as concat_all,
		(date_part('year', f.dt_lead_and_prospect)::varchar
			|| lpad(date_part('month', f.dt_lead_and_prospect)::varchar, 2, '0'))::int  as concat_month,
		count(f.dt_lead_and_prospect) as _count
	from fact_supply_potential_listings f
	join dim_contacts_and_prospects cp
	  on f.cap_id = cp.sk_cap_id
			and ((cp.status != 'Descartado'
	  		and cp.automatically_discarded is not true
	  		and cp.self_service is false)
	  	or cp.self_service is true)
	left join dim_region r
		on cp.region_id = r.id
	group by r.long_region_name, r.city_name, date_part('year', f.dt_lead_and_prospect), date_part('month', f.dt_lead_and_prospect), date_part('week', f.dt_lead_and_prospect)
	order by r.long_region_name, r.city_name, date_part('year', f.dt_lead_and_prospect), date_part('month', f.dt_lead_and_prospect), date_part('week', f.dt_lead_and_prospect)
),
all_dates as (
	select *
	from all_dates_all
	union all
	select *
	from all_dates_region
),