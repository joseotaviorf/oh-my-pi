DROP TABLE staging.fact_google_daily_cost_attributions;

CREATE TABLE IF NOT EXISTS staging.fact_google_daily_cost_attributions (
	sk_date INTEGER,
	sk_keyword BIGINT,
	keyword_id BIGINT,
	sk_ad BIGINT,
	ad_id BIGINT,
	sk_campaign BIGINT,
	account_id VARCHAR(65535),
	campaign_id VARCHAR(65535),
	adgroup_id VARCHAR(65535),
	mobile_clicks INTEGER,
	tablet_clicks INTEGER,
	computer_clicks INTEGER,
	total_clicks INTEGER,
	mobile_cost DOUBLE PRECISION,
	desktop_cost DOUBLE PRECISION,
	total_cost DOUBLE PRECISION,
	impressions INTEGER,
	desktop_search_impression_share DOUBLE PRECISION,
	mobile_search_impression_share DOUBLE PRECISION,
	tablet_search_impression_share DOUBLE PRECISION,
	desktop_absolute_top_impression_percentage DOUBLE PRECISION,
	mobile_absolute_top_impression_percentage DOUBLE PRECISION,
	tablet_absolute_top_impression_percentage DOUBLE PRECISION,
	ts_load TIMESTAMP
);