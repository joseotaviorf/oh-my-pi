SELECT
    AdvertiserId AS id_advertiser,
    INT(AdsetId) AS id_campaign,
    Advertiser AS advertiser_name,
    SalesAllPc1d AS all_sales,
    Audience AS audience,
    DOUBLE(ECpc) AS cost_per_click,
    Adset AS campaign_name,
    INT(Clicks) AS clicks,
    DOUBLE(OverallCompetitionWin) AS competition_win,
    DOUBLE(AdvertiserCost) AS cost,
    Currency AS currency,
    INT(Displays) AS impressions,
    DOUBLE(RevenueGeneratedPc1d) AS revenue,
    AttributionDate AS dt_attribution,
    year,
    month,
    day
FROM
    datalake_criteo_campaigns_raw.criteo_campaigns
WHERE
    year={year}
    AND month={month}
    AND day={day}
