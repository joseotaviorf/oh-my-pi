DROP TABLE marketing.dim_google_keyword;
CREATE TABLE IF NOT EXISTS marketing.dim_google_keyword (
	sk_keyword BIGINT primary key,
	keyword_id BIGINT,
	keyword_name VARCHAR,
	account_name VARCHAR,
	campaign_name VARCHAR,
	adgroup_name VARCHAR,
	match_type VARCHAR,
	is_test_campaign BOOLEAN,
	ts_load TIMESTAMP
);