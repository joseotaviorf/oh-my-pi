with fact as  (
	select
		coalesce(to_char(date(dd.{0}),'YYYYMMDD')::integer, -1) as sk_date,
		mkt.city_group,
		mkt.mkt_category,
		mkt.mkt_flow,
		mkt.mkt_completion,
		mkt.mkt_origin,
		mkt.mkt_channel,
		mkt.mkt_medium,
		mkt.mkt_source,
		mkt.mkt_platform,
		replace(replace(mkt.utm_campaign, '-', '_'), '_', '.') as utm_campaign,
		mkt.utm_term,
		mkt.utm_content,
		sum(coalesce(mkt.cost,0)) as cost
	from datalake_marketing_costs_prod.daily_costs mkt
	join public.dim_date dd on dd.sk_date =  mkt.id_date
    where funnel_side = 'demand'
	group by 1,2,3,4,5,6,7,8,9,10,11,12,13
),
d_cube as (
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
		sum(coalesce(total_{2}_visits_booked, 0)) as total_{2}_visits_booked,
		sum(coalesce(total_{2}_visits_confirmed, 0)) as total_{2}_visits_confirmed,
		sum(coalesce(total_{2}_offers_submitted, 0)) as total_{2}_offers_submitted,
		sum(coalesce(total_{2}_offers_approved, 0)) as total_{2}_offers_approved,
		sum(coalesce(total_{2}_contracts_signed, 0)) as total_{2}_contracts_signed
	from growth.conversion_points_demand_{2}
	group by 1,2,3,4,5,6,7,8,9,10,11,12,13
)
select
	coalesce(fact.sk_date, d_cube.sk_date) as sk_date,
	coalesce(fact.city_group, d_cube.city_group) as city_group,
	coalesce(fact.mkt_category, d_cube.mkt_category) as mkt_category,
	coalesce(fact.mkt_flow, d_cube.mkt_flow) as mkt_flow,
	coalesce(fact.mkt_completion, d_cube.mkt_completion) as mkt_completion,
	coalesce(fact.mkt_origin, d_cube.mkt_origin) as mkt_origin,
	coalesce(fact.mkt_channel, d_cube.mkt_channel) as mkt_channel,
	coalesce(fact.mkt_medium, d_cube.mkt_medium) as mkt_medium,
	coalesce(fact.mkt_source, d_cube.mkt_source) as mkt_source,
	coalesce(fact.mkt_platform, d_cube.mkt_platform) as mkt_platform,
	coalesce(fact.utm_campaign, d_cube.utm_campaign) as utm_campaign,
	left(coalesce(fact.utm_term, d_cube.utm_term), 500) as  utm_term,
	left(coalesce(fact.utm_content, d_cube.utm_content), 500) as  utm_content,
	coalesce(fact.cost, 0) as cost,
	coalesce(d_cube.total_{2}_sessions, 0) as total_{2}_sessions,
	coalesce(d_cube.total_{2}_active_users, 0) as total_{2}_active_users,
	coalesce(d_cube.total_{2}_visits_booked, 0) as total_{2}_visits_booked,
	coalesce(d_cube.total_{2}_visits_confirmed, 0) as total_{2}_visits_confirmed,
	coalesce(d_cube.total_{2}_offers_submitted, 0) as total_{2}_offers_submitted,
	coalesce(d_cube.total_{2}_offers_approved, 0) as total_{2}_offers_approved,
	coalesce(d_cube.total_{2}_contracts_signed, 0) as total_{2}_contracts_signed,
	getdate() as ts_load
from fact
full outer join d_cube
	on fact.sk_date = d_cube.sk_date
	and coalesce(fact.city_group, '') = coalesce(d_cube.city_group, '')
	and coalesce(fact.mkt_category, '') = coalesce(d_cube.mkt_category, '')
	and coalesce(fact.mkt_flow, '') = coalesce(d_cube.mkt_flow, '')
	and coalesce(fact.mkt_completion, '') = coalesce(d_cube.mkt_completion, '')
	and coalesce(fact.mkt_origin, '') = coalesce(d_cube.mkt_origin, '')
	and coalesce(fact.mkt_channel, '') = coalesce(d_cube.mkt_channel, '')
	and coalesce(fact.mkt_medium, '') = coalesce(d_cube.mkt_medium, '')
	and coalesce(fact.mkt_source, '') = coalesce(d_cube.mkt_source, '')
	and coalesce(fact.mkt_platform, '') = coalesce(d_cube.mkt_platform, '')
	and coalesce(fact.utm_campaign, '') = coalesce(d_cube.utm_campaign, '')
	and coalesce(fact.utm_term, '') = coalesce(d_cube.utm_term, '')
	and coalesce(fact.utm_content, '') = coalesce(d_cube.utm_content, '')
