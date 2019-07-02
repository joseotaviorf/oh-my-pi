select
	dd.{dt_column} as date,
	cast(aaus.id_amplitude as varchar) as id_amplitude,
	aaus.app,
	aaus.city,
	aaus.region,
	aaus.mkt_category,
	aaus.mkt_flow,
	aaus.mkt_completion,
	aaus.mkt_origin,
	aaus.mkt_channel,
	aaus.mkt_medium,
	aaus.mkt_source,
	aaus.mkt_platform,
	aaus.utm_campaign,
	aaus.utm_content,
	aaus.utm_term
from
	datalake_clean.amplitude_active_user_sessions aaus
join
	datalake_clean.ods_dim_date dd
	on dd."date" = aaus.dt_event
group by
	1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16