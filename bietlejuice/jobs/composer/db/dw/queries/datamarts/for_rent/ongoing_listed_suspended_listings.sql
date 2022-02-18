WITH daily_published_and_suspended_listings AS (
SELECT
    f.sk_house_listing,
    f.status_history,
    f.status_change_reason,
    d.date,
    d.week_start,
    d.weekday_name,
    d.month_start,
    d.month_end,
    row_number() OVER(PARTITION BY f.sk_house_listing, d.date ORDER BY f.ts_status_start DESC) AS order_status -- daily order status
FROM 
    fact_house_listing_status f
JOIN 
    dim_date d
        ON d.sk_date BETWEEN nullif(f.sk_status_start_date,-1) AND coalesce(to_char(to_date(nullif(sk_status_end_date,-1),'YYYYMMDD') - 1, 'YYYYMMDD')::BIGINT, to_char(current_date -1, 'YYYYMMDD')::BIGINT)
WHERE 
    f.status_history IN ('publicado','suspenso') -- consider published and suspended status
    AND substring(sk_house_listing,10,12) <> '000' -- consider only listings that already started publication
),
daily_published_suspended_listings_adjusted as (
SELECT
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
FROM 
    daily_published_and_suspended_listings fhs
LEFT JOIN 
    dim_house_listing dhl
        ON fhs.sk_house_listing = dhl.sk_house_listing
WHERE 
    fhs.order_status = 1 -- consider last status on the day
    AND fhs.weekday_name = 'Sunday' -- filter that indicates it will be grouped by week
)
SELECT
	week_start,
	weeks_since_publication,
	status_history,
	CASE
        WHEN status_history = 'suspenso' THEN status_change_reason
    	ELSE NULL 
    END AS status_change_reason,
	sk_house_listing,
    current_timestamp AS ts_load
FROM 
    daily_published_suspended_listings_adjusted;