SELECT
	id AS sk_nps_campaign,
	campaign_name AS name,
	main_channel,
	business_context,
	customer_journey,
	purpose,
	customer_type,
	partner_name,
	metric_group,
	ts_created,
	current_timestamp AS ts_load
FROM 
	(SELECT * FROM datalake_tracksale.campaign
	UNION ALL
	SELECT * FROM datalake_casa_mineira_tracksale.campaign) -- we are merging historical data from Casa Mineira's Tracksale account