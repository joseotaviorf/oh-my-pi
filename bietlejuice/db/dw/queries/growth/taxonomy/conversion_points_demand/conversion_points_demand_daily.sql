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
	sum(coalesce(ds1.daily_count, 0)) as total_daily_demand_sessions
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
	sum(coalesce(dau1.daily_count, 0)) as total_daily_demand_dau
from
	growth.taxonomy_demand_active_users dau1
group by 1,2,3,4,5,6,7,8,9,10,11,12,13
),
demand as (
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
    coalesce(vb1.total_daily_visits_booked, 0) as total_daily_visits_booked,
    coalesce(vc1.total_daily_visits_confirmed,0) as total_daily_visits_confirmed,
    coalesce(os1.total_daily_offers_submitted,0) as total_daily_offers_submitted,
    coalesce(oa1.total_daily_offers_approved,0) as total_daily_offers_approved,
    coalesce(cs1.total_daily_contracts_signed,0) as total_daily_contracts_signed
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
)
select 
	demand.*,
	coalesce(sed.total_daily_demand_sessions,0) as total_daily_sessions,
	coalesce(dau1.total_daily_demand_dau,0) as total_daily_active_users
from demand demand
left join demand_session sed on
	demand.sk_date = sed.sk_date
	and (coalesce(demand.city_group,'') = coalesce(sed.city_group,''))
	and (coalesce(demand.city,'') = coalesce(sed.city,'')) 
	and (coalesce(demand.mkt_category,'') = coalesce(sed.mkt_category,'')) 
	and (coalesce(demand.mkt_flow,'') = coalesce(sed.mkt_flow,''))
	and (coalesce(demand.mkt_completion,'') = coalesce(sed.mkt_completion,''))
	and (coalesce(demand.mkt_channel,'') = coalesce(sed.mkt_channel,''))
	and (coalesce(demand.mkt_medium,'') = coalesce(sed.mkt_medium,''))
	and (coalesce(demand.mkt_source,'') = coalesce(sed.mkt_source,''))
	and (coalesce(demand.mkt_platform,'') = coalesce(sed.mkt_platform,''))
	and (coalesce(demand.utm_campaign,'') = coalesce(sed.utm_campaign,''))
	and (coalesce(demand.utm_content,'') = coalesce(sed.utm_content,''))
	and (coalesce(demand.utm_term,'') = coalesce(sed.utm_term,''))
left join demand_dau dau1 on
	demand.sk_date = dau1.sk_date
	and (coalesce(demand.city_group,'') = coalesce(dau1.city_group,''))
	and (coalesce(demand.city,'') = coalesce(dau1.city,'')) 
	and (coalesce(demand.mkt_category,'') = coalesce(dau1.mkt_category,'')) 
	and (coalesce(demand.mkt_flow,'') = coalesce(dau1.mkt_flow,''))
	and (coalesce(demand.mkt_completion,'') = coalesce(dau1.mkt_completion,''))
	and (coalesce(demand.mkt_channel,'') = coalesce(dau1.mkt_channel,''))
	and (coalesce(demand.mkt_medium,'') = coalesce(dau1.mkt_medium,''))
	and (coalesce(demand.mkt_source,'') = coalesce(dau1.mkt_source,''))
	and (coalesce(demand.mkt_platform,'') = coalesce(dau1.mkt_platform,''))
	and (coalesce(demand.utm_campaign,'') = coalesce(dau1.utm_campaign,''))
	and (coalesce(demand.utm_content,'') = coalesce(dau1.utm_content,''))
	and (coalesce(demand.utm_term,'') = coalesce(dau1.utm_term,''))
union
select
    sed.sk_date,
	sed.city_group,
	sed.city,
	sed.mkt_category,
	sed.mkt_flow,
	sed.mkt_completion,
	sed.mkt_channel,
	sed.mkt_medium,
	sed.mkt_source,
	sed.mkt_platform,
	sed.utm_campaign,
	sed.utm_content,
	sed.utm_term,
    coalesce(dem.total_daily_visits_booked, 0) as total_daily_visits_booked,
    coalesce(dem.total_daily_visits_confirmed, 0) as total_daily_visits_confirmed,
    coalesce(dem.total_daily_offers_submitted, 0) as total_daily_offers_submitted,
    coalesce(dem.total_daily_offers_approved, 0) as total_daily_offers_approved,
    coalesce(dem.total_daily_contracts_signed, 0) as total_daily_contracts_signed,
    sed.total_daily_demand_sessions as total_daily_sessions,
    dau1.total_daily_demand_dau as total_daily_active_users
from demand_session sed
left join demand dem on
	sed.sk_date = dem.sk_date
	and (coalesce(sed.city_group,'') = coalesce(dem.city_group,''))
	and (coalesce(sed.city,'') = coalesce(dem.city,'')) 
	and (coalesce(sed.mkt_category,'') = coalesce(dem.mkt_category,'')) 
	and (coalesce(sed.mkt_flow,'') = coalesce(dem.mkt_flow,''))
	and (coalesce(sed.mkt_completion,'') = coalesce(dem.mkt_completion,''))
	and (coalesce(sed.mkt_channel,'') = coalesce(dem.mkt_channel,''))
	and (coalesce(sed.mkt_medium,'') = coalesce(dem.mkt_medium,''))
	and (coalesce(sed.mkt_source,'') = coalesce(dem.mkt_source,''))
	and (coalesce(sed.mkt_platform,'') = coalesce(dem.mkt_platform,''))
	and (coalesce(sed.utm_campaign,'') = coalesce(dem.utm_campaign,''))
	and (coalesce(sed.utm_content,'') = coalesce(dem.utm_content,''))
	and (coalesce(sed.utm_term,'') = coalesce(dem.utm_term,''))
left join demand_dau dau1 on
	sed.sk_date = dau1.sk_date
	and (coalesce(sed.city_group,'') = coalesce(dau1.city_group,''))
	and (coalesce(sed.city,'') = coalesce(dau1.city,'')) 
	and (coalesce(sed.mkt_category,'') = coalesce(dau1.mkt_category,'')) 
	and (coalesce(sed.mkt_flow,'') = coalesce(dau1.mkt_flow,''))
	and (coalesce(sed.mkt_completion,'') = coalesce(dau1.mkt_completion,''))
	and (coalesce(sed.mkt_channel,'') = coalesce(dau1.mkt_channel,''))
	and (coalesce(sed.mkt_medium,'') = coalesce(dau1.mkt_medium,''))
	and (coalesce(sed.mkt_source,'') = coalesce(dau1.mkt_source,''))
	and (coalesce(sed.mkt_platform,'') = coalesce(dau1.mkt_platform,''))
	and (coalesce(sed.utm_campaign,'') = coalesce(dau1.utm_campaign,''))
	and (coalesce(sed.utm_content,'') = coalesce(dau1.utm_content,''))
	and (coalesce(sed.utm_term,'') = coalesce(dau1.utm_term,''))