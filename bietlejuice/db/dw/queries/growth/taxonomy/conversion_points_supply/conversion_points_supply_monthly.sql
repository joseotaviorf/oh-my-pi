with leads as (
 select
 tx1.sk_date,
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
 sum(coalesce(tx1.daily_count, 0)) as total_daily_leads
from
 growth.taxonomy_leads tx1
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
 ls1.mkt_channel,
 ls1.mkt_medium,
 ls1.mkt_source,
 ls1.mkt_platform,
 ls1.utm_campaign,
 ls1.utm_content,
 ls1.utm_term,
 sum(coalesce(ls1.monthly_count, 0)) as total_monthly_sessions
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
 ls1.mkt_channel,
 ls1.mkt_medium,
 ls1.mkt_source,
 ls1.mkt_platform,
 ls1.utm_campaign,
 ls1.utm_content,
 ls1.utm_term,
 sum(coalesce(ls1.monthly_count, 0)) as total_monthly_active_users
from
 growth.taxonomy_supply_active_users ls1
group by 1,2,3,4,5,6,7,8,9,10,11,12,13
), supply as (
select
 to_char(dd.month_start, 'yyyyMMdd')::integer as sk_month_start_date,
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
 sum(coalesce(tx1.total_daily_leads,0)) as total_monthly_leads,
 sum(coalesce(ls1.total_daily_listings, 0)) as total_monthly_listings
from
 leads tx1
left join listings ls1
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
 ),
users as (
select
 to_char(dd.month_start, 'yyyyMMdd')::integer as sk_month_start_date,
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
 max(coalesce(tx1.total_monthly_sessions, 0)) as total_monthly_sessions,
 max(coalesce(ls1.total_monthly_active_users, 0)) as total_monthly_active_users
from
 sessions tx1
left join active_users ls1
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
	 supply.*,
	 coalesce(us.total_monthly_sessions, 0) as total_monthly_sessions,
	 coalesce(us.total_monthly_active_users, 0) as total_monthly_active_users
from
	supply supply
left join users us
 on us.sk_month_start_date = supply.sk_month_start_date
 and (us.city_group = supply.city_group)
 and (us.city = supply.city)
 and (us.mkt_category = supply.mkt_category)
 and (us.mkt_flow = supply.mkt_flow)
 and (us.mkt_completion = supply.mkt_completion)
 and (us.mkt_channel = supply.mkt_channel)
 and (us.mkt_medium = supply.mkt_medium)
 and (us.mkt_source = supply.mkt_source)
 and (coalesce(us.mkt_platform,'') = coalesce(supply.mkt_platform,''))
 and (coalesce(us.utm_campaign,'') = coalesce(supply.utm_campaign,''))
 and (coalesce(us.utm_term,'') = coalesce(supply.utm_term,''))
 and (coalesce(us.utm_content,'') = coalesce(supply.utm_content,''))
UNION
select
	 us.sk_month_start_date,
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
	 coalesce(supply.total_monthly_leads, 0) as total_monthly_leads,
	 coalesce(supply.total_monthly_listings, 0) as total_monthly_listings,
	 coalesce(us.total_monthly_sessions, 0) as total_monthly_sessions,
	 coalesce(us.total_monthly_active_users, 0) as total_monthly_active_users
from
	users us
left join supply supply
 on us.sk_month_start_date = supply.sk_month_start_date
 and (us.city_group = supply.city_group)
 and (us.city = supply.city)
 and (us.mkt_category = supply.mkt_category)
 and (us.mkt_flow = supply.mkt_flow)
 and (us.mkt_completion = supply.mkt_completion)
 and (us.mkt_channel = supply.mkt_channel)
 and (us.mkt_medium = supply.mkt_medium)
 and (us.mkt_source = supply.mkt_source)
 and (coalesce(us.mkt_platform,'') = coalesce(supply.mkt_platform,''))
 and (coalesce(us.utm_campaign,'') = coalesce(supply.utm_campaign,''))
 and (coalesce(us.utm_content,'') = coalesce(supply.utm_content,''))
 and (coalesce(us.utm_term,'') = coalesce(supply.utm_term,''))