CREATE TABLE IF NOT EXISTS staging.dim_google_ads_keyword (
	sk_keyword BIGINT,
	keyword_id BIGINT,
	keyword_name VARCHAR,
	account_name VARCHAR,
	campaign_name VARCHAR,
	adgroup_name VARCHAR,
	match_type VARCHAR,
	ts_load TIMESTAMP
)