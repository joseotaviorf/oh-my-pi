SELECT
    advertiser_id AS id_advertiser,
    CAST(campaign_id AS BIGINT) AS id_campaign,
    CAST(adgroup_id AS BIGINT) AS id_adgroup,
    CAST(ad_id AS BIGINT) AS id_ad,
    campaign_name,
    adgroup_name,
    ad_name,
    CAST(province_id AS BIGINT) AS id_province,
    CAST(spend AS DOUBLE) AS spend,
    CAST(impressions AS BIGINT) AS impressions,
    CAST(reach AS BIGINT) AS reach,
    CAST(clicks AS BIGINT) AS clicks,
    DATE(dt_stat) AS dt_stat,
    year,
    month,
    day
FROM
    datalake_tiktok_campaigns_raw.tiktok_campaigns
WHERE
    dt_stat BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
