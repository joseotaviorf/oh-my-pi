SELECT
  advertiser_id AS id_advertiser,
  campaign_id AS id_campaign,
  ad_set_id AS id_ad_set,
  advertiser AS advertiser_name,
  campaign AS campaign_name,
  ad_set,
  region,
  zip_code,
  CAST(cost AS DOUBLE),
  CAST(clicks AS DOUBLE),
  CAST(displays AS DOUBLE),
  TO_DATE(day) AS dt_report,
  ts_load
FROM datalake_gsheets_raw.criteo_costs