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
FROM datalake_tracksale.campaign
