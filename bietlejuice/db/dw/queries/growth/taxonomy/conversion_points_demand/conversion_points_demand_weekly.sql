with booking as (
select
	vb1.sk_date,
	vb1.city_group,
	vb1.city,
	vb1.mkt_category,
	vb1.mkt_flow,
	vb1.mkt_completion,
	vb1.mkt_channel,
	vb1.mkt_medium,
	vb1.mkt_source,
	vb1.mkt_platform,
	vb1.utm_campaign,
	vb1.utm_content,
	vb1.utm_term,
	sum(coalesce(vb1.daily_count, 0)) as total_daily_visits_booked
from
	growth.taxonomy_visits_booked vb1
group by 1,2,3,4,5,6,7,8,9,10,11,12,13
),
visit_confirmed as (
select
	vc1.sk_date,
	vc1.city_group,
	vc1.city,
	vc1.mkt_category,
	vc1.mkt_flow,
	vc1.mkt_completion,
	vc1.mkt_channel,
	vc1.mkt_medium,
	vc1.mkt_source,
	vc1.mkt_platform,
	vc1.utm_campaign,
	vc1.utm_content,
	vc1.utm_term,
	sum(coalesce(vc1.daily_count, 0)) as total_daily_visits_confirmed
from
	growth.taxonomy_visits_completed vc1
group by 1,2,3,4,5,6,7,8,9,10,11,12,13
),
offer_submitted as (
select
	os1.sk_date,
	os1.city_group,
	os1.city,
	os1.mkt_category,
	os1.mkt_flow,
	os1.mkt_completion,
	os1.mkt_channel,
	os1.mkt_medium,
	os1.mkt_source,
	os1.mkt_platform,
	os1.utm_campaign,
	os1.utm_content,
	os1.utm_term,
	sum(coalesce(os1.daily_count, 0)) as total_daily_offers_submitted
from
	growth.taxonomy_offers_submitted os1
group by 1,2,3,4,5,6,7,8,9,10,11,12,13
),
offer_approved as (
select
	oa1.sk_date,
	oa1.city_group,
	oa1.city,
	oa1.mkt_category,
	oa1.mkt_flow,
	oa1.mkt_completion,
	oa1.mkt_channel,
	oa1.mkt_medium,
	oa1.mkt_source,
	oa1.mkt_platform,
	oa1.utm_campaign,
	oa1.utm_content,
	oa1.utm_term,
	sum(coalesce(oa1.daily_count, 0)) as total_daily_offers_approved
from
	growth.taxonomy_offers_approved oa1
group by 1,2,3,4,5,6,7,8,9,10,11,12,13
),
contract_signed as (
select
	cs1.sk_date,
	cs1.city_group,
	cs1.city,
	cs1.mkt_category,
	cs1.mkt_flow,
	cs1.mkt_completion,
	cs1.mkt_channel,
	cs1.mkt_medium,
	cs1.mkt_source,
	cs1.mkt_platform,
	cs1.utm_campaign,
	cs1.utm_content,
	cs1.utm_term,
	sum(coalesce(cs1.daily_count, 0)) as total_daily_contracts_signed
from
	growth.taxonomy_contracts_signed cs1
group by 1,2,3,4,5,6,7,8,9,10,11,12,13
),
demand_session as
(
select
	ds1.sk_date,
	ds1.city_group,
	ds1.city,
	ds1.mkt_category,
	ds1.mkt_flow,
	ds1.mkt_completion,
	ds1.mkt_channel,
	ds1.mkt_medium,
	ds1.mkt_source,
	ds1.mkt_platform,
	ds1.utm_campaign,
	ds1.utm_content,
	ds1.utm_term,
	sum(coalesce(ds1.weekly_count, 0)) as total_weekly_demand_sessions
from
	growth.taxonomy_demand_active_user_sessions ds1
group by 1,2,3,4,5,6,7,8,9,10,11,12,13
),
demand_dau as (
select
	dau1.sk_date,
	dau1.city_group,
	dau1.city,
	dau1.mkt_category,
	dau1.mkt_flow,
	dau1.mkt_completion,
	dau1.mkt_channel,
	dau1.mkt_medium,
	dau1.mkt_source,
	dau1.mkt_platform,
	dau1.utm_campaign,
	dau1.utm_content,
	dau1.utm_term,
	sum(coalesce(dau1.weekly_count, 0)) as total_weekly_demand_dau
from
	growth.taxonomy_demand_active_users dau1
group by 1,2,3,4,5,6,7,8,9,10,11,12,13
),
demand as (
select
    to_char(dd.week_start, 'yyyyMMdd')::integer as sk_week_start_date,
	vb1.city_group,
	vb1.city,
	vb1.mkt_category,
	vb1.mkt_flow,
	vb1.mkt_completion,
	vb1.mkt_channel,
	vb1.mkt_medium,
	vb1.mkt_source,
	vb1.mkt_platform,
	vb1.utm_campaign,
	vb1.utm_content,
	vb1.utm_term,
    sum(coalesce(vb1.total_daily_visits_booked, 0)) as total_weekly_visits_booked,
    sum(coalesce(vc1.total_daily_visits_confirmed,0)) as total_weekly_visits_confirmed,
    sum(coalesce(os1.total_daily_offers_submitted,0)) as total_weekly_offers_submitted,
    sum(coalesce(oa1.total_daily_offers_approved,0)) as total_weekly_offers_approved,
    sum(coalesce(cs1.total_daily_contracts_signed,0)) as total_weekly_contracts_signed
from booking vb1
left join visit_confirmed vc1 on
    vb1.sk_date = vc1.sk_date
	and (coalesce(vb1.city_group,'') = coalesce(vc1.city_group,''))
	and (coalesce(vb1.city,'') = coalesce(vc1.city,'')) 
	and (coalesce(vb1.mkt_category,'') = coalesce(vc1.mkt_category,'')) 
	and (coalesce(vb1.mkt_flow,'') = coalesce(vc1.mkt_flow,''))
	and (coalesce(vb1.mkt_completion,'') = coalesce(vc1.mkt_completion,''))
	and (coalesce(vb1.mkt_channel,'') = coalesce(vc1.mkt_channel,''))
	and (coalesce(vb1.mkt_medium,'') = coalesce(vc1.mkt_medium,''))
	and (coalesce(vb1.mkt_source,'') = coalesce(vc1.mkt_source,''))
	and (coalesce(vb1.mkt_platform,'') = coalesce(vc1.mkt_platform,''))
	and (coalesce(vb1.utm_campaign,'') = coalesce(vc1.utm_campaign,''))
	and (coalesce(vb1.utm_content,'') = coalesce(vc1.utm_content,''))
	and (coalesce(vb1.utm_term,'') = coalesce(vc1.utm_term,''))
left join offer_submitted os1 on
    vb1.sk_date = os1.sk_date
	and (coalesce(vb1.city_group,'') = coalesce(os1.city_group,''))
	and (coalesce(vb1.city,'') = coalesce(os1.city,'')) 
	and (coalesce(vb1.mkt_category,'') = coalesce(os1.mkt_category,'')) 
	and (coalesce(vb1.mkt_flow,'') = coalesce(os1.mkt_flow,''))
	and (coalesce(vb1.mkt_completion,'') = coalesce(os1.mkt_completion,''))
	and (coalesce(vb1.mkt_channel,'') = coalesce(os1.mkt_channel,''))
	and (coalesce(vb1.mkt_medium,'') = coalesce(os1.mkt_medium,''))
	and (coalesce(vb1.mkt_source,'') = coalesce(os1.mkt_source,''))
	and (coalesce(vb1.mkt_platform,'') = coalesce(os1.mkt_platform,''))
	and (coalesce(vb1.utm_campaign,'') = coalesce(os1.utm_campaign,''))
	and (coalesce(vb1.utm_content,'') = coalesce(os1.utm_content,''))
	and (coalesce(vb1.utm_term,'') = coalesce(os1.utm_term,''))
left join offer_approved oa1 on 
    vb1.sk_date = oa1.sk_date
	and (coalesce(vb1.city_group,'') = coalesce(oa1.city_group,''))
	and (coalesce(vb1.city,'') = coalesce(oa1.city,'')) 
	and (coalesce(vb1.mkt_category,'') = coalesce(oa1.mkt_category,'')) 
	and (coalesce(vb1.mkt_flow,'') = coalesce(oa1.mkt_flow,''))
	and (coalesce(vb1.mkt_completion,'') = coalesce(oa1.mkt_completion,''))
	and (coalesce(vb1.mkt_channel,'') = coalesce(oa1.mkt_channel,''))
	and (coalesce(vb1.mkt_medium,'') = coalesce(oa1.mkt_medium,''))
	and (coalesce(vb1.mkt_source,'') = coalesce(oa1.mkt_source,''))
	and (coalesce(vb1.mkt_platform,'') = coalesce(oa1.mkt_platform,''))
	and (coalesce(vb1.utm_campaign,'') = coalesce(oa1.utm_campaign,''))
	and (coalesce(vb1.utm_content,'') = coalesce(oa1.utm_content,''))
	and (coalesce(vb1.utm_term,'') = coalesce(oa1.utm_term,''))
left join contract_signed cs1 on
    vb1.sk_date = cs1.sk_date
	and (coalesce(vb1.city_group,'') = coalesce(cs1.city_group,''))
	and (coalesce(vb1.city,'') = coalesce(cs1.city,'')) 
	and (coalesce(vb1.mkt_category,'') = coalesce(cs1.mkt_category,'')) 
	and (coalesce(vb1.mkt_flow,'') = coalesce(cs1.mkt_flow,''))
	and (coalesce(vb1.mkt_completion,'') = coalesce(cs1.mkt_completion,''))
	and (coalesce(vb1.mkt_channel,'') = coalesce(cs1.mkt_channel,''))
	and (coalesce(vb1.mkt_medium,'') = coalesce(cs1.mkt_medium,''))
	and (coalesce(vb1.mkt_source,'') = coalesce(cs1.mkt_source,''))
	and (coalesce(vb1.mkt_platform,'') = coalesce(cs1.mkt_platform,''))
	and (coalesce(vb1.utm_campaign,'') = coalesce(cs1.utm_campaign,''))
	and (coalesce(vb1.utm_content,'') = coalesce(cs1.utm_content,''))
	and (coalesce(vb1.utm_term,'') = coalesce(cs1.utm_term,''))
join public.dim_date dd
   on vb1.sk_date = dd.sk_date
group by 1,2,3,4,5,6,7,8,9,10,11,12,13
), users as (
select
 to_char(dd.week_start, 'yyyyMMdd')::integer as sk_week_start_date,
 tx1.city_group,
 tx1.city,
 tx1.mkt_category,
 tx1.mkt_flow,
 tx1.mkt_completion,
 tx1.mkt_channel,
 tx1.mkt_medium,
 tx1.mkt_source,
 tx1.mkt_platform,
 tx1.utm_campaign,
 tx1.utm_content,
 tx1.utm_term,
 max(coalesce(tx1.total_weekly_demand_sessions, 0)) as total_weekly_sessions,
 max(coalesce(ls1.total_weekly_demand_dau, 0)) as total_weekly_active_users
from
 demand_session tx1
left join demand_dau ls1
 on ls1.sk_date = tx1.sk_date
 and (ls1.city_group = tx1.city_group)
 and (ls1.city = tx1.city)
 and (ls1.mkt_category = tx1.mkt_category)
 and (ls1.mkt_flow = tx1.mkt_flow)
 and (ls1.mkt_completion = tx1.mkt_completion)
 and (ls1.mkt_channel = tx1.mkt_channel)
 and (ls1.mkt_medium = tx1.mkt_medium)
 and (ls1.mkt_source = tx1.mkt_source)
 and (coalesce(ls1.mkt_platform,'') = coalesce(tx1.mkt_platform,''))
 and (coalesce(ls1.utm_campaign,'') = coalesce(tx1.utm_campaign,''))
 and (coalesce(ls1.utm_term,'') = coalesce(tx1.utm_term,''))
 and (coalesce(ls1.utm_content,'') = coalesce(tx1.utm_content,''))
join public.dim_date dd
   on tx1.sk_date = dd.sk_date
group by 1,2,3,4,5,6,7,8,9,10,11,12,13
)
select 
	demand.*,
    coalesce(us.total_weekly_sessions,0) as total_weekly_sessions,
    coalesce(us.total_weekly_active_users,0) as total_weekly_active_users
from demand demand
left join users us
 on us.sk_week_start_date = demand.sk_week_start_date
 and (us.city_group = demand.city_group)
 and (us.city = demand.city)
 and (us.mkt_category = demand.mkt_category)
 and (us.mkt_flow = demand.mkt_flow)
 and (us.mkt_completion = demand.mkt_completion)
 and (us.mkt_channel = demand.mkt_channel)
 and (us.mkt_medium = demand.mkt_medium)
 and (us.mkt_source = demand.mkt_source)
 and (coalesce(us.mkt_platform,'') = coalesce(demand.mkt_platform,''))
 and (coalesce(us.utm_campaign,'') = coalesce(demand.utm_campaign,''))
 and (coalesce(us.utm_term,'') = coalesce(demand.utm_term,''))
 and (coalesce(us.utm_content,'') = coalesce(demand.utm_content,''))
union
select
    us.sk_week_start_date,
	us.city_group,
	us.city,
	us.mkt_category,
	us.mkt_flow,
	us.mkt_completion,
	us.mkt_channel,
	us.mkt_medium,
	us.mkt_source,
	us.mkt_platform,
	us.utm_campaign,
	us.utm_content,
	us.utm_term,
    coalesce(dem.total_weekly_visits_booked, 0) as total_weekly_visits_booked,
    coalesce(dem.total_weekly_visits_confirmed, 0) as total_weekly_visits_confirmed,
    coalesce(dem.total_weekly_offers_submitted, 0) as total_weekly_offers_submitted,
    coalesce(dem.total_weekly_offers_approved, 0) as total_weekly_offers_approved,
    coalesce(dem.total_weekly_contracts_signed, 0) as total_weekly_contracts_signed,
    coalesce(us.total_weekly_sessions,0) as total_weekly_sessions,
    coalesce(us.total_weekly_active_users,0) as total_weekly_active_users
from users us
left join demand dem on
	us.sk_week_start_date = dem.sk_week_start_date
	and (coalesce(us.city_group,'') = coalesce(dem.city_group,''))
	and (coalesce(us.city,'') = coalesce(dem.city,''))
	and (coalesce(us.mkt_category,'') = coalesce(dem.mkt_category,''))
	and (coalesce(us.mkt_flow,'') = coalesce(dem.mkt_flow,''))
	and (coalesce(us.mkt_completion,'') = coalesce(dem.mkt_completion,''))
	and (coalesce(us.mkt_channel,'') = coalesce(dem.mkt_channel,''))
	and (coalesce(us.mkt_medium,'') = coalesce(dem.mkt_medium,''))
	and (coalesce(us.mkt_source,'') = coalesce(dem.mkt_source,''))
	and (coalesce(us.mkt_platform,'') = coalesce(dem.mkt_platform,''))
	and (coalesce(us.utm_campaign,'') = coalesce(dem.utm_campaign,''))
	and (coalesce(us.utm_content,'') = coalesce(dem.utm_content,''))
	and (coalesce(us.utm_term,'') = coalesce(dem.utm_term,''))