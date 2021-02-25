with daily_published_listings as (
select
        f.sk_sale_listing,
        f.status_history,
        d.date,
        d.week_start,
        d.weekday_name,
        f.sk_status_start_date,
        f.sk_status_end_date,
        f.sk_region,
        row_number() over(partition by f.sk_sale_listing, d.date order by f.ts_status_started desc) as order_status -- daily order status
from sale.fact_listing_status f
join dim_date d
    on d.sk_date BETWEEN NULLIF(f.sk_status_start_date,-1) 
    and coalesce(NULLIF(sk_status_end_date, -1), CAST(REPLACE(CAST(current_date AS VARCHAR), '-', '') AS BIGINT) - 1)
where f.status_history = 'PUBLISHED'
)
, daily_published_listings_with_region as (
select
    fhs.sk_sale_listing,
    fhs.date,
    fhs.week_start,
    fhs.weekday_name,
    fhs.order_status,
    fhs.status_history,
    dr.sk_region,
    dr.name AS region,
    dr.city_name,
    dr.city_group
from daily_published_listings fhs
join dim_region dr
    on dr.sk_region = fhs.sk_region
where fhs.order_status = 1
)
select
    date,
    weekday_name,
    week_start,
    sk_region,
    region,
    city_name,
    city_group,
    count(distinct sk_sale_listing) as ongoing_listings
from daily_published_listings_with_region
group by 1, 2, 3, 4 ,5, 6, 7