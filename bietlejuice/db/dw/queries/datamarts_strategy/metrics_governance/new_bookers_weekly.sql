-- Query to count the number of clients who booked a visit by week
with
first_booking as (
select *
from (
    select
    rf.ods_id,
    rf.sk_client,
    rf.sk_region,
    db.dt_created as first_booking_created_date,
    row_number() over (partition by rf.sk_client order by db.dt_created asc) as rk
    from fact_listing_rent_flows rf
    join dim_booking db
    	on db.sk_booking = rf.sk_booking
    where rf.sk_booking_created_date
)
where rk = 1
)
select
    date_trunc('week',fb.first_booking_created_date) as first_booking_created_week,
    dr.sk_region,
    count(distinct fb.sk_client) as new_bookers_weekly
from first_booking fb
left join fact_listing_rent_flows rf
  on (fb.sk_client = rf.sk_client)
left join dim_date dd
  on rf.sk_contract_signed_date = dd.sk_date
left join dim_region dr
 on fb.sk_region = dr.sk_region
group by 1, 2
order by 1 desc, 2