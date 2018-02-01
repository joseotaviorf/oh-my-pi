drop table if exists growth.ongoing_contracts;
create table growth.ongoing_contracts as

-- Get each date part from the corresponding column and make two concatenations: year+month+week and year+month
-- The concatenation is necessary because Redshift doesn't apply the 'over partition' the same way as Postgres, so
-- the data gets all shuffled up.
-- In addition, two CTE are needed so double counting doesn't happen if all regions are summed up.
with all_dates_all as (
	select
		date_part('year', dd."date") as _year,
		date_part('month', dd."date") as _month,
		date_part('week', dd."date") as _week,
		'QuintoAndar'::varchar as region,
		'QuintoAndar'::varchar as city,
		(date_part('year', dd."date")::varchar
			|| lpad(date_part('month', dd."date")::varchar, 2, '0')
			|| lpad(date_part('week', dd."date")::varchar, 2, '0'))::int  as concat_all,
		(date_part('year', dd."date")::varchar
			|| lpad(date_part('month', dd."date")::varchar, 2, '0'))::int  as concat_month,
		count(distinct(liq.sk_contract)) as c
	from
		public.fact_liquidity_property_scheduling liq
	left join
		public.dim_contract c
		on liq.sk_contract = c.sk_contract
	left join
		public.dim_property p
		on p.sk_property = liq.sk_property
	left join
		public.dim_region r
		on p.regiao_id = r.sk_region
	right join
		public.dim_date dd
		on c.dt_contract_start <= dd."date"
		and coalesce(dt_contract_annulment,dt_contract_intended_end) >= dd."date"
	where
		dd."date" <= current_date
		and c.dt_contract_start <= current_date
		and c.contract_status <> 'Cancelado'
		and liq.sk_contract_signed_date <> -1
		and dd."date" >= '2016-01-01'
	group by date_part('year', dd."date"), date_part('month', dd."date"), date_part('week', dd."date")
		order by date_part('year', dd."date"), date_part('month', dd."date"), date_part('week', dd."date")
),
all_dates_region as (
	select
		date_part('year', dd."date") as _year,
		date_part('month', dd."date") as _month,
		date_part('week', dd."date") as _week,
		r.long_region_name as region,
		r.city_name as city,
		(date_part('year', dd."date")::varchar
			|| lpad(date_part('month', dd."date")::varchar, 2, '0')
			|| lpad(date_part('week', dd."date")::varchar, 2, '0'))::int  as concat_all,
		(date_part('year', dd."date")::varchar
			|| lpad(date_part('month', dd."date")::varchar, 2, '0'))::int  as concat_month,
		count(distinct(liq.sk_contract)) as c
	from
		public.fact_liquidity_property_scheduling liq
	left join
		public.dim_contract c
		on liq.sk_contract = c.sk_contract
	left join
		public.dim_property p
		on p.sk_property = liq.sk_property
	left join
		public.dim_region r
		on p.regiao_id = r.sk_region
	right join
		public.dim_date dd
		on c.dt_contract_start <= dd."date"
		and coalesce(dt_contract_annulment,dt_contract_intended_end) >= dd."date"
	where
		dd."date" <= current_date
		and c.dt_contract_start <= current_date
		and c.contract_status <> 'Cancelado'
		and liq.sk_contract_signed_date <> -1
		and dd."date" >= '2016-01-01'
	group by  r.long_region_name, r.city_name, date_part('year', dd."date"), date_part('month', dd."date"), date_part('week', dd."date")
		order by  r.long_region_name, r.city_name, date_part('year', dd."date"), date_part('month', dd."date"), date_part('week', dd."date")
),
all_dates as (
	select *
	from all_dates_all
	union all
	select *
	from all_dates_region
),