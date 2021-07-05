SELECT
    INT(`Campaign ID`) AS id_campaign,
    `Advertiser Name` AS advertiser_name,
    `All Sales` AS all_sales,
    `Audience` AS audience,
    DOUBLE(CPC) AS cost_per_click,
    `Campaign Name` AS campaign_name,
    INT(clicks),
    DOUBLE(`Comp. Win`) AS composition_win,
    DOUBLE(cost),
    currency,
    INT(impressions),
    DOUBLE(revenue),
    `Cost Attribution Date` AS dt_cost_attribution,
    year,
    month,
    day
FROM
    datalake_marketing_costs_raw.criteo_campaigns
WHERE
    year={year}
    AND month={month}
    AND day={day}
