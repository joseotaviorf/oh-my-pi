SELECT
	SHA2(CONCAT(id_external_customer, id_video, campaign_name, ad_group_name, device), 256) AS id,
	id_video,
	id_external_customer,
	id_ad_group,
	id_campaign,
	ad_group_name,
	campaign_name,
	(campaign_name LIKE 'ZEBRA%') AS is_test_campaign,
	clicks,
	cost,
	device,
	impressions,
	account_descriptive_name,
	acc,
	report_type,
	load_date,
	dt_load,
	dt_created
FROM
    datalake_marketing_hub_clean.google_videos_performance_report
WHERE 
    load_date = DATE('{year}-{month}-{day}')