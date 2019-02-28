with t_dau as (
select
	adau.event_date,
	adau.amplitude_id,
	adau.session_id,
	adau.city,
	adau.region,
	adau.platform,
	adau.utm_source,
	adau.utm_medium,
	adau.utm_campaign,
	case when lower(adau.utm_campaign) like '%branded%' then 'Branded'
		 when lower(adau.utm_campaign) like '%institucional%' then 'Branded'
		 else 'Outro' end as branded,
	adau.utm_content,
	adau.utm_term,
	case
		when adau.app = '170698' then 'demand'
		when adau.app = '183047' then 'supply'
	end as app
from datalake_raw.amplitude_daily_active_users adau
where try(date(event_date)) = date('{dt}')
	and nullif(adau.app,'') is not null
	and trim(adau.country) = 'Brazil'
)
select
    dau.app,
	dau.event_date,
	dau.amplitude_id,
	dau.session_id,
	dau.city,
	dau.region,
	dau.platform,
	dau.utm_source,
	dau.utm_medium,
	dau.utm_campaign,
    dau.utm_content,
	dau.utm_term,
	coalesce(ts.category, td.category, 'Not Mapped') as mkt_category,
	coalesce(ts.flow, td.flow, 'Not Mapped') as mkt_flow,
	coalesce(ts.completion, td.completion, 'Not Mapped') as mkt_completion,
	coalesce(ts.channel, td.channel, 'Not Mapped') as mkt_channel,
	coalesce(ts.medium, td.medium, 'Not Mapped') as mkt_medium,
	coalesce(ts.source, td.source, 'Not Mapped') as mkt_source,
	coalesce(ts.platform, td.platform, 'Not Mapped') as mkt_platform
from t_dau dau
left join datalake_raw.taxonomy_supply_dau ts
	on dau.app = 'supply'
	and	lower(trim(ts.utm_medium)) = lower(trim(dau.utm_medium))
	and lower(trim(ts.utm_source)) = lower(trim(dau.utm_source))
	and lower(trim(ts.app_type)) = lower(trim(dau.platform))
	and lower(trim(ts.branded)) = lower(trim(dau.branded))
left join datalake_raw.taxonomy_demand_dau td
	on dau.app = 'demand'
	and	lower(trim(td.utm_medium)) = lower(trim(dau.utm_medium))
	and lower(trim(td.utm_source)) = lower(trim(dau.utm_source))
	and lower(trim(td.app_type)) = lower(trim(dau.platform))
	and lower(trim(td.branded)) = lower(trim(dau.branded))