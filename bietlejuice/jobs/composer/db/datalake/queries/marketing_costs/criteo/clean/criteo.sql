SELECT
    INT(`Campaign ID`) as id_campaign,
    `Advertiser Name` as advertiser_name,
    `All Sales` as all_sales,
    `Audience` as audience,
    DOUBLE(CPC) as cost_per_click,
    `Campaign Name` as campaign_name,
    INT(clicks),
    DOUBLE(`Comp. Win`) as composition_win,
    DOUBLE(cost),
    currency,
    INT(impressions),
    DOUBLE(revenue),
    year,
    month,
    day
FROM datalake_marketing_costs_raw.criteo
WHERE
    year={year} and month={month} and day={day}
