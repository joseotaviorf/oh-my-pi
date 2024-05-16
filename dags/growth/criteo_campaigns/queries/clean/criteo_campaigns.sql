SELECT
    AdvertiserId AS id_advertiser,
    INT(AdsetId) AS id_campaign,
    Advertiser AS advertiser_name,
    SalesAllPc1d AS all_sales,
    Audience AS audience,
    DOUBLE(ECpc) AS cost_per_click,
    Adset AS campaign_name,
    'BR' AS country_code,
    INT(Clicks) AS clicks,
    DOUBLE(OverallCompetitionWin) AS competition_win,
    DOUBLE(AdvertiserCost) AS cost,
    Currency AS currency,
    INT(Displays) AS impressions,
    DOUBLE(RevenueGeneratedPc1d) AS revenue,
    AttributionDate AS dt_attribution
FROM
    datalake_criteo_campaigns_raw.criteo_campaigns
WHERE
    AttributionDate BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
