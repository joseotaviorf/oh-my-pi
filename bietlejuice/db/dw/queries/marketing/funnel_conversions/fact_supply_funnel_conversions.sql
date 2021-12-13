with fact as  (
	select
		coalesce(to_char(date(dd.{0}),'YYYYMMDD')::integer, -1) as sk_date,
		city_group,
		mkt_category,
		mkt_flow,
		mkt_completion,
		mkt_origin,
		mkt_channel,
		mkt_medium,
		mkt_source,
		mkt_platform,
		replace(replace(utm_campaign, '-', '_'), '_', '.') as utm_campaign,
		utm_term,
		utm_content,
		sum(coalesce(cost,0)) as cost
	from datalake_marketing_costs_prod.daily_costs mkt
	join public.dim_date dd on dd.sk_date =  mkt.id_date
	where funnel_side in ('supply','affiliates')
	group by 1,2,3,4,5,6,7,8,9,10,11,12,13
),
s_cube as (
	select
		coalesce({1}, -1) as sk_date,
		city_group,
		mkt_category,
		mkt_flow,
		mkt_completion,
		mkt_origin,
		mkt_channel,
		mkt_medium,
		mkt_source,
		case when mkt_platform in ('App Android', 'App iOS', 'Web Mobile') then 'Mobile'
			 when mkt_platform = 'Web Desktop' then 'Desktop'
			 else mkt_platform end as mkt_platform,
		-- Trying to minimize unmatching due to wrong separator parametrization in amplitude
		replace(replace(utm_campaign, '-', '_'), '_', '.') as utm_campaign,
		utm_term,
		utm_content,
		sum(coalesce(total_{2}_sessions, 0)) as total_{2}_sessions,
		sum(coalesce(total_{2}_active_users, 0)) as total_{2}_active_users,
		sum(coalesce(total_{2}_leads, 0)) as total_{2}_leads,
		sum(coalesce(total_{2}_prospects, 0)) as total_{2}_prospects,
		sum(coalesce(total_{2}_qualifieds, 0)) as total_{2}_qualifieds,
		sum(coalesce(total_{2}_opportunities, 0)) as total_{2}_opportunities,
		sum(coalesce(total_{2}_listings, 0)) as total_{2}_listings
	from growth.conversion_points_supply_{2}
	group by 1,2,3,4,5,6,7,8,9,10,11,12,13
)
select
	coalesce(fact.sk_date, s_cube.sk_date) as sk_date,
	coalesce(fact.city_group, s_cube.city_group) as city_group,
	coalesce(fact.mkt_category, s_cube.mkt_category) as mkt_category,
	coalesce(fact.mkt_flow, s_cube.mkt_flow) as mkt_flow,
	coalesce(fact.mkt_completion, s_cube.mkt_completion) as mkt_completion,
	coalesce(fact.mkt_origin, s_cube.mkt_origin) as mkt_origin,
	coalesce(fact.mkt_channel, s_cube.mkt_channel) as mkt_channel,
	coalesce(fact.mkt_medium, s_cube.mkt_medium) as mkt_medium,
	coalesce(fact.mkt_source, s_cube.mkt_source) as mkt_source,
	coalesce(fact.mkt_platform, s_cube.mkt_platform) as mkt_platform,
	coalesce(fact.utm_campaign, s_cube.utm_campaign) as utm_campaign,
	coalesce(fact.utm_term, s_cube.utm_term) as  utm_term,
	coalesce(fact.utm_content, s_cube.utm_content) as  utm_content,
	coalesce(fact.cost, 0) as cost,
	coalesce(s_cube.total_{2}_sessions, 0) as total_{2}_sessions,
	coalesce(s_cube.total_{2}_active_users, 0) as total_{2}_active_users,
	coalesce(s_cube.total_{2}_leads, 0) as total_{2}_leads,
	coalesce(s_cube.total_{2}_prospects, 0) as total_{2}_prospects,
	coalesce(s_cube.total_{2}_qualifieds, 0) as total_{2}_qualifieds,
	coalesce(s_cube.total_{2}_opportunities, 0) as total_{2}_opportunities,
	coalesce(s_cube.total_{2}_listings, 0) as total_{2}_listings,
	getdate() as ts_load
from fact
full outer join s_cube
	on fact.sk_date = s_cube.sk_date
	and coalesce(fact.city_group, '') = coalesce(s_cube.city_group, '')
	and coalesce(fact.mkt_category, '') = coalesce(s_cube.mkt_category, '')
	and coalesce(fact.mkt_flow, '') = coalesce(s_cube.mkt_flow, '')
	and coalesce(fact.mkt_completion, '') = coalesce(s_cube.mkt_completion, '')
	and coalesce(fact.mkt_origin, '') = coalesce(s_cube.mkt_origin, '')
	and coalesce(fact.mkt_channel, '') = coalesce(s_cube.mkt_channel, '')
	and coalesce(fact.mkt_medium, '') = coalesce(s_cube.mkt_medium, '')
	and coalesce(fact.mkt_source, '') = coalesce(s_cube.mkt_source, '')
	and coalesce(fact.mkt_platform, '') = coalesce(s_cube.mkt_platform, '')
	and coalesce(fact.utm_campaign, '') = coalesce(s_cube.utm_campaign, '')
	and coalesce(fact.utm_term, '') = coalesce(s_cube.utm_term, '')
	and coalesce(fact.utm_content, '') = coalesce(s_cube.utm_content, '')