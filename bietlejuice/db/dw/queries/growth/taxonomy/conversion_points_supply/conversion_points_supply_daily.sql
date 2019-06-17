with leads as (
 select
 tx1.sk_date,
 tx1.city_group,
 tx1.city,
 tx1.mkt_category,
 tx1.mkt_flow,
 tx1.mkt_completion,
 tx1.mkt_origin,
 tx1.mkt_channel,
 tx1.mkt_medium,
 tx1.mkt_source,
 tx1.mkt_platform,
 tx1.utm_campaign,
 tx1.utm_content,
 tx1.utm_term,
 sum(coalesce(tx1.daily_count, 0)) as total_daily_leads
from
 growth.taxonomy_leads tx1
group by 1,2,3,4,5,6,7,8,9,10,11,12,13
),
prospects as (
 select
 p.sk_date,
 p.city_group,
 p.city,
 p.mkt_category,
 p.mkt_flow,
 p.mkt_completion,
 p.mkt_channel,
 p.mkt_medium,
 p.mkt_source,
 p.mkt_platform,
 p.utm_campaign,
 p.utm_content,
 p.utm_term,
 sum(coalesce(p.daily_count, 0)) as total_daily_prospects
from
 growth.taxonomy_prospects p
group by 1,2,3,4,5,6,7,8,9,10,11,12,13
),
qualifieds as (
 select
 q.sk_date,
 q.city_group,
 q.city,
 q.mkt_category,
 q.mkt_flow,
 q.mkt_completion,
 q.mkt_channel,
 q.mkt_medium,
 q.mkt_source,
 q.mkt_platform,
 q.utm_campaign,
 q.utm_content,
 q.utm_term,
 sum(coalesce(q.daily_count, 0)) as total_daily_qualifieds
from
 growth.taxonomy_qualifieds q
group by 1,2,3,4,5,6,7,8,9,10,11,12,13
),
opportunities as (
 select
 op.sk_date,
 op.city_group,
 op.city,
 op.mkt_category,
 op.mkt_flow,
 op.mkt_completion,
 op.mkt_channel,
 op.mkt_medium,
 op.mkt_source,
 op.mkt_platform,
 op.utm_campaign,
 op.utm_content,
 op.utm_term,
 sum(coalesce(op.daily_count, 0)) as total_daily_opportunities
from
 growth.taxonomy_opportunities op
group by 1,2,3,4,5,6,7,8,9,10,11,12,13
),
listings as (
select
 ls1.sk_date,
 ls1.city_group,
 ls1.city,
 ls1.mkt_category,
 ls1.mkt_flow,
 ls1.mkt_completion,
 ls1.mkt_origin,
 ls1.mkt_channel,
 ls1.mkt_medium,
 ls1.mkt_source,
 ls1.mkt_platform,
 ls1.utm_campaign,
 ls1.utm_content,
 ls1.utm_term,
 sum(coalesce(ls1.daily_count, 0)) as total_daily_listings
from
 growth.taxonomy_listings ls1
group by 1,2,3,4,5,6,7,8,9,10,11,12,13
),
sessions as (
select
 ls1.sk_date,
 ls1.city_group,
 ls1.city,
 ls1.mkt_category,
 ls1.mkt_flow,
 ls1.mkt_completion,
 ls1.mkt_origin,
 ls1.mkt_channel,
 ls1.mkt_medium,
 ls1.mkt_source,
 ls1.mkt_platform,
 ls1.utm_campaign,
 ls1.utm_content,
 ls1.utm_term,
 sum(coalesce(ls1.daily_count, 0)) as total_daily_sessions
from
 growth.taxonomy_supply_active_user_sessions ls1
group by 1,2,3,4,5,6,7,8,9,10,11,12,13
),
active_users as (
select
 ls1.sk_date,
 ls1.city_group,
 ls1.city,
 ls1.mkt_category,
 ls1.mkt_flow,
 ls1.mkt_completion,
 ls1.mkt_origin,
 ls1.mkt_channel,
 ls1.mkt_medium,
 ls1.mkt_source,
 ls1.mkt_platform,
 ls1.utm_campaign,
 ls1.utm_content,
 ls1.utm_term,
 sum(coalesce(ls1.daily_count, 0)) as total_daily_active_users
from
 growth.taxonomy_supply_active_users ls1
group by 1,2,3,4,5,6,7,8,9,10,11,12,13
), supply as (
select
 tx1.*,
 coalesce(p.total_daily_prospects, 0) as total_daily_prospects,
 coalesce(q.total_daily_qualifieds, 0) as total_daily_qualifieds,
 coalesce(op.total_daily_opportunities, 0) as total_daily_opportunities,
 coalesce(ls1.total_daily_listings, 0) as total_daily_listings
from
 leads tx1
left join prospects p
 on p.sk_date = tx1.sk_date
 and (coalesce(p.city_group,'') = coalesce(tx1.city_group,''))
 and (coalesce(p.city,'') = coalesce(tx1.city,''))
 and (coalesce(p.mkt_category,'') = coalesce(tx1.mkt_category,''))
 and (coalesce(p.mkt_flow,'') = coalesce(tx1.mkt_flow,''))
 and (coalesce(p.mkt_completion,'') = coalesce(tx1.mkt_completion,''))
 and (coalesce(p.mkt_channel,'') = coalesce(tx1.mkt_channel,''))
 and (coalesce(p.mkt_medium,'') = coalesce(tx1.mkt_medium,''))
 and (coalesce(p.mkt_source,'') = coalesce(tx1.mkt_source,''))
 and (coalesce(p.mkt_platform,'') = coalesce(tx1.mkt_platform,''))
 and (coalesce(p.utm_campaign,'') = coalesce(tx1.utm_campaign,''))
 and (coalesce(p.utm_term,'') = coalesce(tx1.utm_term,''))
 and (coalesce(p.utm_content,'') = coalesce(tx1.utm_content,''))
left join qualifieds q
 on q.sk_date = tx1.sk_date
 and (coalesce(q.city_group,'') = coalesce(tx1.city_group,''))
 and (coalesce(q.city,'') = coalesce(tx1.city,''))
 and (coalesce(q.mkt_category,'') = coalesce(tx1.mkt_category,''))
 and (coalesce(q.mkt_flow,'') = coalesce(tx1.mkt_flow,''))
 and (coalesce(q.mkt_completion,'') = coalesce(tx1.mkt_completion,''))
 and (coalesce(q.mkt_channel,'') = coalesce(tx1.mkt_channel,''))
 and (coalesce(q.mkt_medium,'') = coalesce(tx1.mkt_medium,''))
 and (coalesce(q.mkt_source,'') = coalesce(tx1.mkt_source,''))
 and (coalesce(q.mkt_platform,'') = coalesce(tx1.mkt_platform,''))
 and (coalesce(q.utm_campaign,'') = coalesce(tx1.utm_campaign,''))
 and (coalesce(q.utm_term,'') = coalesce(tx1.utm_term,''))
 and (coalesce(q.utm_content,'') = coalesce(tx1.utm_content,''))
left join opportunities op
 on op.sk_date = tx1.sk_date
 and (coalesce(op.city_group,'') = coalesce(tx1.city_group,''))
 and (coalesce(op.city,'') = coalesce(tx1.city,''))
 and (coalesce(op.mkt_category,'') = coalesce(tx1.mkt_category,''))
 and (coalesce(op.mkt_flow,'') = coalesce(tx1.mkt_flow,''))
 and (coalesce(op.mkt_completion,'') = coalesce(tx1.mkt_completion,''))
 and (coalesce(op.mkt_channel,'') = coalesce(tx1.mkt_channel,''))
 and (coalesce(op.mkt_medium,'') = coalesce(tx1.mkt_medium,''))
 and (coalesce(op.mkt_source,'') = coalesce(tx1.mkt_source,''))
 and (coalesce(op.mkt_platform,'') = coalesce(tx1.mkt_platform,''))
 and (coalesce(op.utm_campaign,'') = coalesce(tx1.utm_campaign,''))
 and (coalesce(op.utm_term,'') = coalesce(tx1.utm_term,''))
 and (coalesce(op.utm_content,'') = coalesce(tx1.utm_content,''))
left join listings ls1
 on ls1.sk_date = tx1.sk_date
 and (coalesce(ls1.city_group,'') = coalesce(tx1.city_group,''))
 and (coalesce(ls1.city,'') = coalesce(tx1.city,''))
 and (coalesce(ls1.mkt_category,'') = coalesce(tx1.mkt_category,''))
 and (coalesce(ls1.mkt_flow,'') = coalesce(tx1.mkt_flow,''))
 and (coalesce(ls1.mkt_completion,'') = coalesce(tx1.mkt_completion,''))
 and (coalesce(ls1.mkt_channel,'') = coalesce(tx1.mkt_channel,''))
 and (coalesce(ls1.mkt_medium,'') = coalesce(tx1.mkt_medium,''))
 and (coalesce(ls1.mkt_source,'') = coalesce(tx1.mkt_source,''))
 and (coalesce(ls1.mkt_platform,'') = coalesce(tx1.mkt_platform,''))
 and (coalesce(ls1.utm_campaign,'') = coalesce(tx1.utm_campaign,''))
 and (coalesce(ls1.utm_term,'') = coalesce(tx1.utm_term,''))
 and (coalesce(ls1.utm_content,'') = coalesce(tx1.utm_content,''))
 ),
users as (
select
 tx1.*,
 coalesce(ls1.total_daily_active_users, 0) as total_daily_active_users
from
 sessions tx1
left join active_users ls1
 on ls1.sk_date = tx1.sk_date
 and (ls1.city_group = tx1.city_group)
 and (ls1.city = tx1.city)
 and (ls1.mkt_category = tx1.mkt_category)
 and (ls1.mkt_flow = tx1.mkt_flow)
 and (ls1.mkt_completion = tx1.mkt_completion)
 and (ls1.mkt_origin = tx1.mkt_origin)
 and (ls1.mkt_channel = tx1.mkt_channel)
 and (ls1.mkt_medium = tx1.mkt_medium)
 and (ls1.mkt_source = tx1.mkt_source)
 and (coalesce(ls1.mkt_platform,'') = coalesce(tx1.mkt_platform,''))
 and (coalesce(ls1.utm_campaign,'') = coalesce(tx1.utm_campaign,''))
 and (coalesce(ls1.utm_term,'') = coalesce(tx1.utm_term,''))
 and (coalesce(ls1.utm_content,'') = coalesce(tx1.utm_content,''))
)
select
	supply.*,
	coalesce(us.total_daily_sessions, 0) as total_daily_sessions,
	coalesce(us.total_daily_active_users, 0) as total_daily_active_users
from
	supply supply
left join users us
 on us.sk_date = supply.sk_date
 and (coalesce(us.city_group,'') = coalesce(supply.city_group,''))
 and (coalesce(us.city,'') = coalesce(supply.city,''))
 and (coalesce(us.mkt_category,'') = coalesce(supply.mkt_category,''))
 and (coalesce(us.mkt_flow,'') = coalesce(supply.mkt_flow,''))
 and (coalesce(us.mkt_completion,'') = coalesce(supply.mkt_completion,''))
 and (coalesce(us.mkt_channel,'') = coalesce(supply.mkt_channel,''))
 and (coalesce(us.mkt_medium,'') = coalesce(supply.mkt_medium,''))
 and (coalesce(us.mkt_source,'') = coalesce(supply.mkt_source,''))
 and (coalesce(us.mkt_platform,'') = coalesce(supply.mkt_platform,''))
 and (coalesce(us.utm_campaign,'') = coalesce(supply.utm_campaign,''))
 and (coalesce(us.utm_term,'') = coalesce(supply.utm_term,''))
 and (coalesce(us.utm_content,'') = coalesce(supply.utm_content,''))
UNION
select
	 us.sk_date,
	 us.city_group,
	 us.city,
	 us.mkt_category,
	 us.mkt_flow,
	 us.mkt_completion,
	 us.mkt_origin,
	 us.mkt_channel,
	 us.mkt_medium,
	 us.mkt_source,
	 us.mkt_platform,
	 us.utm_campaign,
	 us.utm_content,
	 us.utm_term,
	 coalesce(supply.total_daily_leads, 0) as total_daily_leads,
	 coalesce(supply.total_daily_prospects, 0) as total_daily_prospects,
     coalesce(supply.total_daily_qualifieds, 0) as total_daily_qualifieds,
     coalesce(supply.total_daily_opportunities, 0) as total_daily_opportunities,
	 coalesce(supply.total_daily_listings, 0) as total_daily_listings,
	 coalesce(us.total_daily_sessions, 0) as total_daily_sessions,
	 coalesce(us.total_daily_active_users, 0) as total_daily_active_users
from
	users us
left join supply supply
 on us.sk_date = supply.sk_date
 and (coalesce(us.city_group,'') = coalesce(supply.city_group,''))
 and (coalesce(us.city,'') = coalesce(supply.city,''))
 and (coalesce(us.mkt_category,'') = coalesce(supply.mkt_category,''))
 and (coalesce(us.mkt_flow,'') = coalesce(supply.mkt_flow,''))
 and (coalesce(us.mkt_completion,'') = coalesce(supply.mkt_completion,''))
 and (coalesce(us.mkt_channel,'') = coalesce(supply.mkt_channel,''))
 and (coalesce(us.mkt_medium,'') = coalesce(supply.mkt_medium,''))
 and (coalesce(us.mkt_source,'') = coalesce(supply.mkt_source,''))
 and (coalesce(us.mkt_platform,'') = coalesce(supply.mkt_platform,''))
 and (coalesce(us.utm_campaign,'') = coalesce(supply.utm_campaign,''))
 and (coalesce(us.utm_content,'') = coalesce(supply.utm_content,''))
 and (coalesce(us.utm_term,'') = coalesce(supply.utm_term,''))