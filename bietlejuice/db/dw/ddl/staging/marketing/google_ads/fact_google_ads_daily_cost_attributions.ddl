DROP TABLE staging.fact_google_ads_daily_cost_attributions;

CREATE TABLE IF NOT EXISTS staging.fact_google_ads_daily_cost_attributions (
	sk_date INTEGER,
	sk_keyword BIGINT,
	keyword_id BIGINT,
	sk_ad BIGINT,
	ad_id BIGINT,
	account_id VARCHAR(65535),
	campaign_id VARCHAR(65535),
	adgroup_id VARCHAR(65535),
	mobile_clicks INTEGER,
	tablet_clicks INTEGER,
	computer_clicks INTEGER,
	total_clicks INTEGER,
	total_cost DOUBLE PRECISION,
	impressions INTEGER,
	ts_load TIMESTAMP
);