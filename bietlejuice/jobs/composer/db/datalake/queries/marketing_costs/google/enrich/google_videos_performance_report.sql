SELECT
	CONCAT(id_external_customer, '-', id_video, '-', campaign_name) AS id,
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
	load_date,
	dt_load,
	dt_created
FROM
    datalake_marketing_hub_clean.google_videos_performance_report
WHERE 
    load_date = DATE('{year}-{month}-{day}')