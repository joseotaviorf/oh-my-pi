SELECT
	id,
	campaign_name,
	NULLIF(REGEXP_EXTRACT(description,'(\\[business\\=)(\\w+)',2),'') AS business_context,
	NULLIF(REGEXP_EXTRACT(description,'(\\[step\\=)(\\w+)',2),'') AS customer_journey,
	NULLIF(REGEXP_EXTRACT(description,'(\\[type\\=)(\\w+)',2),'') AS purpose,
	NULLIF(REGEXP_EXTRACT(description,'(\\[customer\\=)(\\w+)',2),'') AS customer_type,
	NULLIF(REGEXP_EXTRACT(campaign_name,'(Parceria\\sPrime\\sB2B\\:\\sPPs\\s-\\s)(.+)(\\s\\()',2),'') as partner_name,
	NULLIF(REGEXP_EXTRACT(description,'(\\[group\\=)(\\w+)',2),'') AS metric_group,
	main_channel,
	ts_created
FROM datalake_tracksale_clean.campaign
