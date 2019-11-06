-- Re-Rentals based on nr_renting
with ordered_rentals as (
select
	coalesce(dc.dt_start, dc.dt_entrance) as rental_date,
	date_trunc('week',coalesce(dc.dt_start, dc.dt_entrance)) as rental_week_start,
	date_trunc('month',coalesce(dc.dt_start, dc.dt_entrance)) as rental_month_start,
	fhl.sk_house_listing,
	fhl.nr_renting,
	dc.status,
	dc.sk_contract,
	row_number() over (partition by dhl.id_house order by fhl.sk_house_listing) as row_number_renting,
	fhl.sk_region
from dim_contract dc
join fact_house_listings fhl
  on dc.sk_contract = fhl.sk_contract
join dim_house_listing dhl
  on dhl.sk_house_listing = fhl.sk_house_listing
where date(coalesce(dc.dt_start, dc.dt_entrance)) < current_date -- we know we may have future dates for dt_start
  and fhl.nr_renting > 1
)
select
	ord.rental_date,
	ord.rental_week_start,
	ord.rental_month_start,
	ord.sk_region,
	count(distinct ord.sk_contract) as new_rentals_daily,
	sum(count(distinct ord.sk_contract)) over(partition by date_trunc('week',ord.rental_week_start), ord.sk_region) as new_rentals_weekly,
	sum(count(distinct ord.sk_contract)) over(partition by date_trunc('month',ord.rental_month_start), ord.sk_region) as new_rentals_monthly
from ordered_rentals ord
where ord.row_number_renting > 1 and ord.status in ('Ativo', 'Finalizado') -- consider only contracts that are active or were active at a given period
group by 1, 2, 3, 4
