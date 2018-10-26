CREATE TABLE IF NOT EXISTS marketing.dim_google_ads_keyword (
	sk_keyword BIGINT,
	keyword_id BIGINT,
	keyword_name VARCHAR,
	account_name VARCHAR,
	campaign_name VARCHAR,
	adgroup_name VARCHAR,
	match_type VARCHAR,
	dt_created VARCHAR,
	ts_load TIMESTAMP
)