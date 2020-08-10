SELECT
	id AS sk_nps_campaign,
	campaign_name AS name,
	main_channel,
	regexp_extract(description,'(\\[business\\=)(\\w+)',2) AS business_context,
	regexp_extract(description,'(\\[step\\=)(\\w+)',2) AS customer_journey,
	regexp_extract(description,'(\\[type\\=)(\\w+)',2) AS purpose,
	regexp_extract(description,'(\\[customer\\=)(\\w+)',2) AS customer_type,
    regexp_extract(campaign_name,'(Parceria\\sPrime\\sB2B\\:\\sPPs\\s-\\s)(.+)(\\s\\()',2) as partner_name,
	regexp_extract(description,'(\\[group\\=)(\\w+)',2) AS metric_group,
	ts_created,
	current_timestamp AS ts_load
FROM datalake_tracksale_clean.campaign

