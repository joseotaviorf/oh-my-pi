CREATE TABLE IF NOT EXISTS staging.dim_google_ads_keyword (
	sk_keyword BIGINT,
	keyword_id BIGINT,
	keyword_name VARCHAR(65535),
	account_name VARCHAR(65535),
	campaign_name VARCHAR(65535),
	adgroup_name VARCHAR(65535),
	created_dt VARCHAR
)
