with fact as  (
	select
		coalesce(sk_date, -1) as sk_date,
		city_group,
		mkt_category,
		mkt_flow,
		mkt_completion,
		mkt_channel,
		mkt_medium,
		mkt_source,
		mkt_platform,
		replace(utm_campaign, '_', '.') as utm_campaign,
		utm_term,
		utm_content,
		sum(coalesce(cost,0)) as cost
	from marketing.fact_marketing_daily_costs
	where side = 'supply'
	group by 1,2,3,4,5,6,7,8,9,10,11,12
),
s_cube as (
	select
		coalesce(sk_date, -1) as sk_date,
		city_group,
		mkt_category,
		mkt_flow,
		mkt_completion,
		mkt_channel,
		mkt_medium,
		mkt_source,
		case when mkt_platform in ('App Android', 'App iOS', 'Web Mobile') then 'Mobile'
			 when mkt_platform = 'Web Desktop' then 'Desktop'
			 else mkt_platform end as mkt_platform,
		-- Trying to minimize unmatching due to wrong separator parametrization in amplitude
		replace(replace(utm_campaign, '-', '_'), '_', '.') as utm_campaign,
		-- Due to limitations in Google API we need to remove excess data for each type of medium
		case when mkt_channel = 'Online Paid' and mkt_source = 'Google' and mkt_medium = 'Display' then NULL
			else utm_term end as utm_term,
		case when mkt_channel = 'Online Paid' and mkt_source = 'Google' and mkt_medium <> 'Display' then NULL
			else utm_content end as utm_content,
		sum(coalesce(total_daily_sessions, 0)) as total_daily_sessions,
		sum(coalesce(total_daily_active_users, 0)) as total_daily_active_users,
		sum(coalesce(total_daily_leads, 0)) as total_daily_leads,
		sum(coalesce(total_daily_listings, 0)) as total_daily_listings
	from growth.conversion_points_supply_daily
	group by 1,2,3,4,5,6,7,8,9,10,11,12
)
select
	coalesce(fact.sk_date, s_cube.sk_date) as sk_date,
	coalesce(fact.city_group, s_cube.city_group) as city_group,
	coalesce(fact.mkt_category, s_cube.mkt_category) as mkt_category,
	coalesce(fact.mkt_flow, s_cube.mkt_flow) as mkt_flow,
	coalesce(fact.mkt_completion, s_cube.mkt_completion) as mkt_completion,
	coalesce(fact.mkt_channel, s_cube.mkt_channel) as mkt_channel,
	coalesce(fact.mkt_medium, s_cube.mkt_medium) as mkt_medium,
	coalesce(fact.mkt_source, s_cube.mkt_source) as mkt_source,
	coalesce(fact.mkt_platform, s_cube.mkt_platform) as mkt_platform,
	coalesce(fact.utm_campaign, s_cube.utm_campaign) as utm_campaign,
	coalesce(fact.utm_term, s_cube.utm_term) as  utm_term,
	coalesce(fact.utm_content, s_cube.utm_content) as  utm_content,
	coalesce(fact.cost, 0) as cost,
	coalesce(s_cube.total_daily_sessions, 0) as total_daily_sessions,
	coalesce(s_cube.total_daily_active_users, 0) as total_daily_active_users,
	coalesce(s_cube.total_daily_leads, 0) as total_daily_leads,
	coalesce(s_cube.total_daily_listings, 0) as total_daily_listings,
	getdate() as ts_load
from fact
full outer join s_cube
	on fact.sk_date = s_cube.sk_date
	and coalesce(fact.city_group, '') = coalesce(s_cube.city_group, '')
	and coalesce(fact.mkt_category, '') = coalesce(s_cube.mkt_category, '')
	and coalesce(fact.mkt_flow, '') = coalesce(s_cube.mkt_flow, '')
	and coalesce(fact.mkt_completion, '') = coalesce(s_cube.mkt_completion, '')
	and coalesce(fact.mkt_channel, '') = coalesce(s_cube.mkt_channel, '')
	and coalesce(fact.mkt_medium, '') = coalesce(s_cube.mkt_medium, '')
	and coalesce(fact.mkt_source, '') = coalesce(s_cube.mkt_source, '')
	and coalesce(fact.mkt_platform, '') = coalesce(s_cube.mkt_platform, '')
	and coalesce(fact.utm_campaign, '') = coalesce(s_cube.utm_campaign, '')
	and coalesce(fact.utm_term, '') = coalesce(s_cube.utm_term, '')
	and coalesce(fact.utm_content, '') = coalesce(s_cube.utm_content, '')