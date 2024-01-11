WITH daily_published_and_suspended_listings AS (
SELECT /*+ RANGE_JOIN(f, 19000) */
    f.sk_house_listing,
    f.status_history,
    f.status_change_reason,
    d.date,
    d.week_start,
    d.weekday_name,
    d.month_start,
    d.month_end,
    ROW_NUMBER() OVER(PARTITION BY f.sk_house_listing, d.date ORDER BY f.ts_status_start DESC) AS order_status -- daily order status
FROM
    dw_rent.fact_house_listing_status f
JOIN
    dw_public.dim_date d
        ON d.sk_date BETWEEN nullif(f.sk_status_start_date,-1) AND COALESCE(CAST(DATE_FORMAT(date_sub(to_date(string(nullif(sk_status_end_date,-1)),'yyyyMMdd'), 1),'yyyyMMdd') AS BIGINT), CAST(DATE_FORMAT(DATE_SUB(CURRENT_DATE(),1), 'yyyyMMdd') as BIGINT))
WHERE
    f.status_history IN ('publicado','suspenso', 'PUBLISHED', 'SUSPENDED') -- consider published and suspended status
    AND COALESCE(f.status_change_reason, '') <> 'RENTED'
    AND SUBSTRING(sk_house_listing,10,12) <> '000' -- consider only listings that already started publication
),
daily_published_suspended_listings_adjusted AS (
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
    CAST(DATEDIFF(fhs.week_start, DATE_TRUNC('WEEK',dhl.ts_publication))/7 AS BIGINT) AS weeks_since_publication
FROM
    daily_published_and_suspended_listings fhs
LEFT JOIN
    dw_rent.dim_house_listing dhl
        ON fhs.sk_house_listing = dhl.sk_house_listing
WHERE
    fhs.order_status = 1 -- consider last status on the day
    AND fhs.weekday_name = 'Sunday' -- filter that indicates it will be grouped by week
)
SELECT
    sk_house_listing,
    week_start,
    weeks_since_publication,
    status_history,
    CASE
        WHEN status_history IN ('suspenso', 'SUSPENDED') THEN status_change_reason
        ELSE NULL
    END AS status_change_reason
FROM
    daily_published_suspended_listings_adjusted
