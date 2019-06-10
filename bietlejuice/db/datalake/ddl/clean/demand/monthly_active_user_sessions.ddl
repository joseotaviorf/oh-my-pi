DROP TABLE datalake_clean.monthly_active_user_sessions;

CREATE EXTERNAL TABLE datalake_clean.amplitude_monthly_active_user_sessions (
    date string,
	id_amplitude string,
	id_session string,
	app string,
	city string,
	region string,
	mkt_category string,
	mkt_flow string,
	mkt_completion string,
	mkt_origin string,
	mkt_channel string,
	mkt_medium string,
	mkt_source string,
	mkt_platform string,
	utm_campaign string,
	utm_content string,
	utm_term string
)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/demand/monthly_active_user_sessions/'