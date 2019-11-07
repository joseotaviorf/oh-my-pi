-- Supply allocation

with
first_listings as (
--filter only first listings because supply costs are only applied to these listings
--since the supply cost is available for the period after jan/2018,
  -- we'll also filter listings published from the second half of jan/2018 and on
select
	sk_house_listing,
	city_group,
	ts_listing_version_start,
	date_trunc('month',ts_listing_version_start) as month_publication,
	extract(day from ts_listing_version_start) as day_month,
	case when extract(day from ts_listing_version_start) <= 15 then '1H-Month'
	     when extract(day from ts_listing_version_start) > 15 then '2H-Month' end as part_month
from datamarts_strategy.house_listings
where listing_category_start = 'First Listing'
  and date_trunc('month',ts_listing_version_start) > '2018-01-15'
),
first_listings_published_month as (
-- create new month to join with the supply costs for each month
-- the total supply cost in a month will be applied to listings published in the second half of the same month and the first half of the next month
select
	*,
	case when part_month = '1H-Month' then add_months(month_publication,-1)
		 when part_month = '2H-Month' then month_publication
	end as month_publication_new
from first_listings
where city_group is not null
),
join_supply_costs_listings as (
select
	lpm.month_publication_new,
	lpm.city_group,
	sc.costs_monthly,
	count(distinct lpm.sk_house_listing) as listings_published
from first_listings_published_month lpm
left join datamarts_strategy.supply_daily_costs sc
  on lpm.month_publication_new = sc.month_start
  and lpm.city_group = sc.city_group
group by 1, 2, 3
order by 1 desc, 2
),
cost_by_first_listing as (
select
	month_publication_new,
	city_group,
	costs_monthly/listings_published::float as supply_cost
from join_supply_costs_listings
)
select
	fl.sk_house_listing,
	fl.city_group,
	sc.supply_cost
from first_listings_published_month fl
left join cost_by_first_listing sc
  on fl.month_publication_new = sc.month_publication_new
  and fl.city_group = sc.city_group