-- Query to count the number of clients who booked a visit by week
select
    date_trunc('week',dd.date) as booking_created_week,
    rf.sk_region,
    count(distinct rf.sk_client) as bookers_weekly
from fact_listing_rent_flows rf
left join dim_date dd
  on rf.sk_booking_created_date = dd.sk_date
group by 1, 2
order by 1 desc, 2
