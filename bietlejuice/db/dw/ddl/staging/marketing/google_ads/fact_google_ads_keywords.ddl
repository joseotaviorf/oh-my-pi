CREATE TABLE IF NOT EXISTS staging.fact_googleads_daily_keywords (
	sk_keyword BIGINT,
	keyword_name VARCHAR(65535),
	match_type VARCHAR(65535),
	total_cost DOUBLE PRECISION,
	impressions INTEGER,
	clicks INTEGER,
	sk_date INTEGER,
	rank BIGINT
);