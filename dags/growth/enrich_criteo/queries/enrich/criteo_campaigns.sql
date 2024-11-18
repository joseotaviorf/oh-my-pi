SELECT 
    id_advertiser,
    id_campaign,
    id_ad_set,
    advertiser_name,
    campaign_name,
    ad_set,
    region,
    zip_code,
    cost,
    sales,
    audience,
    clicks,
    cpc,
    ctr,
    displays,
    exposed_users,
    reach,
    visits,
    win_rate,
    bounce_rate,
    cost_per_visit,
    cpo,
    cvr,
    dt_report,
    ts_load,
    YEAR(dt_report) AS year,
    MONTH(dt_report) AS month,
    DAY(dt_report) AS day
FROM 
    datalake_gsheets_clean.criteo_costs
WHERE 
    DATE(dt_report) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
