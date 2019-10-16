-- Table with listing daily events (for listings published since 2018/jan)
-- Every listing will have all days between listing_version_start and contract_created_date or listing_version_end
    -- or current_date
with
house_listing_contracts as (
select
	dhl.sk_house_listing,
	dr.city_group,
	dhl.ts_listing_version_start,
	dhl.ts_listing_version_end,
	dhl.ts_last_de_publication,
	case when dhl.ts_last_de_publication is not null
	      and dhl.status = 'despublicado'
	      and  rf_c.sk_contract_signed_date is null then dhl.ts_last_de_publication end as last_unpublished_date,
	dhl.status,
	date(nullif(rf_c.sk_contract_signed_date,-1)) as contract_signed_date,
	date(nullif(rf_c.sk_contract_created_date,-1)) as contract_created_date
from dim_house_listing dhl
left join fact_listing_rent_flows rf_c
  on dhl.sk_house_listing = rf_c.sk_house_listing and rf_c.sk_contract_signed_date > 0
left join fact_house_listings fhl
  on dhl.sk_house_listing = fhl.sk_house_listing
left join dim_region dr
  on fhl.sk_region = dr.sk_region
where version > 0 and dhl.ts_listing_version_start >= '2018-01-01'
),
house_listing_all_days as (
select
    hlc.*,
    dd.date,
    datediff(day,date(hlc.ts_listing_version_start),dd.date) as ongoing_days,
    max(datediff(day,date(hlc.ts_listing_version_start),dd.date)) over(partition by hlc.sk_house_listing) as max_days_publi
from house_listing_contracts hlc
left join dim_date dd
  on dd.date between date(hlc.ts_listing_version_start)
     and coalesce(
     			  coalesce(
     			  		   coalesce(hlc.contract_created_date, date(hlc.ts_listing_version_end) - interval '1 day'),
     			   date(last_unpublished_date)),
     	 current_date - interval '1 day')
),
house_listing_all_days_booking as (
select
    hlad.*,
    count(distinct rf_b.sk_booking) as total_bookings_listing_daily
from house_listing_all_days hlad
left join fact_listing_rent_flows rf_b
  on hlad.sk_house_listing = rf_b.sk_house_listing
  and hlad.date = date(rf_b.sk_booking_created_date)
  and rf_b.sk_booking_created_date > 0
group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
),
listing_bookings_daily as (
select
    *,
    max(total_bookings_listing_daily) over(partition by sk_house_listing) as max_daily_bookings,
    sum(total_bookings_listing_daily) over(partition by sk_house_listing) as total_bookings_listing,
    sum(total_bookings_listing_daily) over(partition by date, city_group) as total_bookings_daily
from house_listing_all_days_booking
)
select *
from listing_bookings_daily
