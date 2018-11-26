DROP TABLE staging.dim_google_ads_ad;

CREATE TABLE IF NOT EXISTS staging.dim_google_ads_ad (
	sk_ad BIGINT,
	ad_id BIGINT,
	account_name VARCHAR,
	campaign_name VARCHAR,
	adgroup_name VARCHAR,
	image_creative_name VARCHAR,
	ad_type VARCHAR,
	ts_load TIMESTAMP
)