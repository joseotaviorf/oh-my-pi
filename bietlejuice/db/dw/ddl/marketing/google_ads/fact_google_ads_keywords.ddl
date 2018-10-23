CREATE TABLE IF NOT EXISTS marketing.fact_google_ads_daily_keywords (
	sk_keyword BIGINT,
	sk_date INTEGER,
	keyword_id BIGINT,
	account_id VARCHAR(65535),
	campaign_id VARCHAR(65535),
	adgroup_id VARCHAR(65535),
	mobile_clicks INTEGER,
	tablet_clicks INTEGER,
	computer_clicks INTEGER,
	total_clicks INTEGER,
	total_cost DOUBLE PRECISION,
	impressions INTEGER,
	dt_created VARCHAR
);