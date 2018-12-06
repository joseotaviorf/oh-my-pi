DROP TABLE marketing.dim_google_ad;

CREATE TABLE IF NOT EXISTS marketing.dim_google_ad (
	sk_ad BIGINT,
	ad_id BIGINT,
	account_name VARCHAR,
	campaign_name VARCHAR,
	adgroup_name VARCHAR,
	image_creative_name VARCHAR,
	ad_type VARCHAR,
	ts_load TIMESTAMP
)