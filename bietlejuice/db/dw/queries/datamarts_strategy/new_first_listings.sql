-- Define new_first_listings

select
    dd.date as first_listing_date,
    date_trunc('week', dd.date) as first_listing_week_start,
    date_trunc('month', dd.date) as first_listing_month_start,
    lf.sk_region,
    count(distinct lf.sk_house_listing) as new_first_listings_daily,
    sum(count(distinct lf.sk_house_listing)) over(partition by date_trunc('week',dd.date)) as new_first_listings_weekly,
    sum(count(distinct lf.sk_house_listing)) over(partition by date_trunc('month',dd.date)) as new_first_listings_monthly
from public.fact_house_listing_flows lf
  join dim_date dd
  on lf.sk_first_listing_date = dd.sk_date
  and dd.date < current_date
  where lf.sk_first_listing_date > 0
group by 1, 2, 3, 4
order by 1 desc, 2, 3, 4