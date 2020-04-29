DROP TABLE IF EXISTS marketing.fact_affiliate_daily_engagement_cost;

CREATE TABLE IF NOT EXISTS marketing.fact_affiliate_daily_engagement_cost (
	sk_date INTEGER,
	sk_user INTEGER,
	sk_region INTEGER,
	sk_user_affiliate INTEGER,
	sk_user_agent INTEGER,
	affiliate_type VARCHAR(64),
	commission_type VARCHAR(64),
	value_brl NUMERIC(10,2),
	ts_load TIMESTAMP
);
