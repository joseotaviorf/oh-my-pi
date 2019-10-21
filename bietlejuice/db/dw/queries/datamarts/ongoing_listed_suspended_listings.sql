with
daily_published_and_suspended_listings as (
select
    f.sk_house_listing,
    f.status_history,
    f.status_change_reason,
    d.date,
    d.week_start,
    d.weekday_name,
    d.month_start,
    d.month_end,
    row_number() over(partition by f.sk_house_listing, d.date order by f.ts_status_start desc) as order_status -- daily order status
from fact_house_listing_status f
join dim_date d
  on d.sk_date between nullif(f.sk_status_start_date,-1) and coalesce(to_char(to_date(nullif(sk_status_end_date,-1),'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, to_char(current_date -1, 'YYYYMMDD')::bigint)
where f.status_history in ('publicado','suspenso') -- consider published and suspended status
  and substring(sk_house_listing,10,12) <> '000' -- consider only listings that already started publication
),
daily_published_suspended_listings_adjusted as (
select
    fhs.sk_house_listing,
    fhs.date,
    fhs.week_start,
    fhs.weekday_name,
    fhs.month_start,
    fhs.month_end,
    fhs.order_status,
    fhs.status_history,
    fhs.status_change_reason,
    date_diff('week', dhl.ts_publication, fhs.week_start) as weeks_since_publication
from daily_published_and_suspended_listings fhs
left join dim_house_listing dhl
  on fhs.sk_house_listing = dhl.sk_house_listing
where fhs.order_status = 1 -- consider last status on the day
  and fhs.weekday_name = 'Sunday' -- filter that indicates it will be grouped by week
)
select
	week_start,
	weeks_since_publication,
	status_history,
	case when status_history = 'suspenso' then status_change_reason	else null end as status_change_reason,
	sk_house_listing
from daily_published_suspended_listings_adjusted
;