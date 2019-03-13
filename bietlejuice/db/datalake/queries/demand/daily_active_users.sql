select
	event_date,
	cast(amplitude_id as varchar) as amplitude_id,
	app,
	city,
	region,
	mkt_category,
	mkt_flow,
	mkt_completion,
	mkt_channel,
	mkt_medium,
	mkt_source,
	mkt_platform
from
	datalake_clean.amplitude_active_user_sessions
group by
	1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12