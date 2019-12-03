with
listing_bookings_costs_daily as (
select
    lb.*,
    cost.costs_daily,
    count(lb.sk_house_listing) over(partition by lb.date, lb.city_group) as listings_daily,
    count(case when total_bookings_listing_daily > 0 then lb.sk_house_listing end) over(partition by lb.date, lb.city_group) as listings_with_bookings_daily,
    dense_rank() over(partition by lb.date, lb.city_group order by lb.ongoing_days desc) as rank_days
from datamarts_strategy.house_listing_daily_events lb
left join datamarts_strategy.demand_daily_costs cost
  on lb.date = cost.date
    and lb.city_group = cost.city_group
where lb.city_group is not null
),
listing_bookings_costs_daily_calc as (
select
    *,
    sum(rank_days) over(partition by date, city_group) as sum_rank_days,
    rank_days::float/(sum(rank_days) over(partition by date, city_group))::float as rank_days_percent,
    case when total_bookings_daily > 0 then costs_daily::float/total_bookings_daily::float else 0 end as cost_per_booking
from listing_bookings_costs_daily
),
house_listing_costs_allocation as (
select
    *,
    cost_per_booking*total_bookings_listing_daily as listing_cost_booking,
    costs_daily*rank_days_percent as listing_cost_days_published,
    costs_daily::float/listings_daily::float as listing_cost_published,
    case when total_bookings_listing_daily > 0 then costs_daily::float/listings_with_bookings_daily::float else 0 end as listing_cost_listing_with_booking
from listing_bookings_costs_daily_calc
)
select
    cost_alloc.sk_house_listing,
    cost_alloc.city_group,
    cost_alloc.ts_listing_version_start,
    cost_alloc.contract_signed_date,
    dhl.house_bedrooms,
    case when dhl.house_bedrooms <= 1 then '1 bedroom'
         when dhl.house_bedrooms = 2 then '2 bedrooms'
         when dhl.house_bedrooms = 3 then '3 bedrooms'
         when dhl.house_bedrooms >= 4 then '4 or more bedrooms'
         end as n_bedrooms,
    dhl.house_listing_rent_price_published as house_listing_rent_price_published,
    case when dhl.house_listing_rent_price_published <= 1000 then '0 - 1000 reais'
         when (dhl.house_listing_rent_price_published > 1000 and dhl.house_listing_rent_price_published <= 2000) then '1000 - 2000 reais'
         when (dhl.house_listing_rent_price_published > 2000 and dhl.house_listing_rent_price_published <= 4000) then '2000 - 4000 reais'
         when dhl.house_listing_rent_price_published > 4000 then '4000 reais or more'
         end as house_listing_rent_price_grouped,
    dhl.house_total_value as total_package_value,
    sum(cost_alloc.listing_cost_booking) as demand_cost_booking,
    sum(cost_alloc.listing_cost_days_published) as demand_cost_days_published,
    sum(cost_alloc.listing_cost_published) as demand_cost_listing_published,
    sum(cost_alloc.listing_cost_listing_with_booking) as demand_cost_listing_with_booking
from house_listing_costs_allocation cost_alloc
left join datamarts_strategy.house_listings dhl
  using(sk_house_listing)
group by 1, 2, 3, 4, 5, 6, 7, 8, 9

