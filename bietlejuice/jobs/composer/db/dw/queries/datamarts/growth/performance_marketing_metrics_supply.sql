with
leads as (
	select
		nullif(f.sk_lead_date, -1) sk_date,
		coalesce(dr.city_group, 'Not Mapped') city_group,
		coalesce(f.mkt_origin,'') mkt_origin,
		coalesce(f.mkt_channel,'') mkt_channel,
		coalesce(f.mkt_medium,'') mkt_medium,
		coalesce(f.mkt_source,'') mkt_source,
		coalesce(dl.utm_campaign,'') utm_campaign,
		coalesce(dl.utm_content,'') utm_content,
		coalesce(dl.utm_term,'') utm_term,
		count(1) as count_lead
	from
		fact_house_listing_flows f
		join dim_lead dl
			on dl.sk_lead = f.sk_lead
		join dim_region dr
			on f.sk_region = dr.sk_region
	where
		f.mkt_origin in ('Owner PWA', 'Price Calculator')
	group by 1,2,3,4,5,6,7,8,9
),
prospects as (
	select
		nullif(f.sk_prospect_date, -1) sk_date,
		coalesce(dr.city_group, 'Not Mapped') city_group,
		coalesce(f.mkt_origin,'') mkt_origin,
		coalesce(f.mkt_channel,'') mkt_channel,
		coalesce(f.mkt_medium,'') mkt_medium,
		coalesce(f.mkt_source,'') mkt_source,
		coalesce(dl.utm_campaign,'') utm_campaign,
		coalesce(dl.utm_content,'') utm_content,
		coalesce(dl.utm_term,'') utm_term,
		count(1) as count_prospect
	from
		fact_house_listing_flows f
		join dim_lead dl
			on dl.sk_lead = f.sk_lead
		join dim_region dr
			on f.sk_region = dr.sk_region
	where
		f.mkt_origin in ('Owner PWA', 'Price Calculator')
	group by 1,2,3,4,5,6,7,8,9
),
qualifieds as (
	select
		nullif(f.sk_qualified_date, -1) sk_date,
		coalesce(dr.city_group, 'Not Mapped') city_group,
		coalesce(f.mkt_origin,'') mkt_origin,
		coalesce(f.mkt_channel,'') mkt_channel,
		coalesce(f.mkt_medium,'') mkt_medium,
		coalesce(f.mkt_source,'') mkt_source,
		coalesce(dl.utm_campaign,'') utm_campaign,
		coalesce(dl.utm_content,'') utm_content,
		coalesce(dl.utm_term,'') utm_term,
		count(1) as count_qualified
	from
		fact_house_listing_flows f
		join dim_lead dl
			on dl.sk_lead = f.sk_lead
		join dim_region dr
			on f.sk_region = dr.sk_region
	where
		f.mkt_origin in ('Owner PWA', 'Price Calculator')
	group by 1,2,3,4,5,6,7,8,9
),
opportunities as (
	select
		nullif(f.sk_opportunity_date, -1) sk_date,
		coalesce(dr.city_group, 'Not Mapped') city_group,
		coalesce(f.mkt_origin,'') mkt_origin,
		coalesce(f.mkt_channel,'') mkt_channel,
		coalesce(f.mkt_medium,'') mkt_medium,
		coalesce(f.mkt_source,'') mkt_source,
		coalesce(dl.utm_campaign,'') utm_campaign,
		coalesce(dl.utm_content,'') utm_content,
		coalesce(dl.utm_term,'') utm_term,
		count(1) as count_opportunity
	from
		fact_house_listing_flows f
		join dim_lead dl
			on dl.sk_lead = f.sk_lead
		join dim_region dr
			on f.sk_region = dr.sk_region
	where
		f.mkt_origin in ('Owner PWA', 'Price Calculator')
	group by 1,2,3,4,5,6,7,8,9
),
listings as (
	select
		nullif(f.sk_first_listing_date, -1) sk_date,
		coalesce(dr.city_group, 'Not Mapped') city_group,
		coalesce(f.mkt_origin,'') mkt_origin,
		coalesce(f.mkt_channel,'') mkt_channel,
		coalesce(f.mkt_medium,'') mkt_medium,
		coalesce(f.mkt_source,'') mkt_source,
		coalesce(dl.utm_campaign,'') utm_campaign,
		coalesce(dl.utm_content,'') utm_content,
		coalesce(dl.utm_term,'') utm_term,
		count(1) as count_first_listing
	from
		fact_house_listing_flows f
		join dim_lead dl
			on dl.sk_lead = f.sk_lead
		join dim_region dr
			on f.sk_region = dr.sk_region
	where
		f.mkt_origin in ('Owner PWA', 'Price Calculator')
	group by 1,2,3,4,5,6,7,8,9
),
results as ( --coincident funnel
	select
		date(coalesce(l.sk_date,p.sk_date,q.sk_date,o.sk_date,fl.sk_date)) as date,
		coalesce(l.city_group,p.city_group,q.city_group,o.city_group,fl.city_group) as city_group,
		coalesce(l.mkt_origin,p.mkt_origin,q.mkt_origin,o.mkt_origin,fl.mkt_origin) as mkt_origin,
		coalesce(l.mkt_channel,p.mkt_channel,q.mkt_channel,o.mkt_channel,fl.mkt_channel) as mkt_channel,
		coalesce(l.mkt_medium,p.mkt_medium,q.mkt_medium,o.mkt_medium,fl.mkt_medium) as mkt_medium,
		coalesce(l.mkt_source,p.mkt_source,q.mkt_source,o.mkt_source,fl.mkt_source) as mkt_source,
		coalesce(l.utm_campaign,p.utm_campaign,q.utm_campaign,o.utm_campaign,fl.utm_campaign) as utm_campaign,
		coalesce(l.utm_content,p.utm_content,q.utm_content,o.utm_content,fl.utm_content) as utm_content,
		coalesce(l.utm_term,p.utm_term,q.utm_term,o.utm_term,fl.utm_term) as utm_term,
		sum(coalesce(l.count_lead,0)) as leads,
		sum(coalesce(p.count_prospect,0)) as prospects,
		sum(coalesce(q.count_qualified,0)) as qualifieds,
		sum(coalesce(o.count_opportunity,0)) as opportunities,
		sum(coalesce(fl.count_first_listing,0)) as first_listings
	from leads l
	full outer join prospects p
		on  l.sk_date      = p.sk_date
		and l.city_group   = p.city_group
		and l.mkt_origin   = p.mkt_origin
		and l.mkt_channel  = p.mkt_channel
		and l.mkt_medium   = p.mkt_medium
		and l.mkt_source   = p.mkt_source
		and l.utm_campaign = p.utm_campaign
		and l.utm_content  = p.utm_content
		and l.utm_term     = p.utm_term
	full outer join qualifieds q
		on  l.sk_date      = q.sk_date
		and l.city_group   = q.city_group
		and l.mkt_origin   = q.mkt_origin
		and l.mkt_channel  = q.mkt_channel
		and l.mkt_medium   = q.mkt_medium
		and l.mkt_source   = q.mkt_source
		and l.utm_campaign = q.utm_campaign
		and l.utm_content  = q.utm_content
		and l.utm_term     = q.utm_term
	full outer join opportunities o
		on  l.sk_date      = o.sk_date
		and l.city_group   = o.city_group
		and l.mkt_origin   = o.mkt_origin
		and l.mkt_channel  = o.mkt_channel
		and l.mkt_medium   = o.mkt_medium
		and l.mkt_source   = o.mkt_source
		and l.utm_campaign = o.utm_campaign
		and l.utm_content  = o.utm_content
		and l.utm_term     = o.utm_term
	full outer join listings fl
		on  l.sk_date      = fl.sk_date
		and l.city_group   = fl.city_group
		and l.mkt_origin   = fl.mkt_origin
		and l.mkt_channel  = fl.mkt_channel
		and l.mkt_medium   = fl.mkt_medium
		and l.mkt_source   = fl.mkt_source
		and l.utm_campaign = fl.utm_campaign
		and l.utm_content  = fl.utm_content
		and l.utm_term     = fl.utm_term
	group by 1,2,3,4,5,6,7,8,9
),
costs as (
	select
		date(nullif(mkt.id_date, -1)) date,
		coalesce(mkt.city_group, 'Not Mapped') city_group,
		coalesce(mkt.mkt_origin,'') mkt_origin,
		coalesce(mkt.mkt_channel,'') mkt_channel,
		coalesce(mkt.mkt_medium,'') mkt_medium,
		coalesce(mkt.mkt_source,'') mkt_source,
		coalesce(mkt.utm_campaign,'') utm_campaign,
		coalesce(mkt.utm_content,'') utm_content,
		coalesce(mkt.utm_term,'') utm_term,
		sum(coalesce(mkt.cost,0)) as cost
	from
		datalake_marketing_costs_prod.daily_costs mkt
	where
		mkt.mkt_origin in ('Owner PWA', 'Price Calculator')
	group by 1,2,3,4,5,6,7,8,9
),
targets as (
	select
		date(nullif(str.date,'')) as date,
		coalesce(nullif(str.city_group,''),'Not Mapped')::varchar as city_group,
		nullif(str.mkt_origin,'')::varchar as mkt_origin,
		nullif(str.mkt_channel,'')::varchar as mkt_channel,
		'' as mkt_medium,
		'' as mkt_source,
		'' as utm_campaign,
		'' as utm_content,
		'' as utm_term,
		sum(nullif(budget,'')::float) as budget,
		sum(nullif(prospects_target,'')::float) as prospects_target,
		sum(nullif(qualifieds_target,'')::float) as qualifieds_target,
		sum(nullif(opportunities_target,'')::float) as opportunities_target,
		sum(nullif(first_listings_target,'')::float) as first_listings_target
	from
		datalake_raw.gsheets_supply_targets_replanning str
	group by 1,2,3,4,5,6,7,8,9
)
select
	coalesce(r.date, c.date,t.date) as date,
	coalesce(r.city_group, c.city_group, t.city_group) as city_group,
	coalesce(r.mkt_origin, c.mkt_origin, t.mkt_origin) as mkt_origin,
	coalesce(r.mkt_channel, c.mkt_channel, t.mkt_channel) as mkt_channel,
	coalesce(r.mkt_medium, c.mkt_medium, t.mkt_medium) as mkt_medium,
	coalesce(r.mkt_source, c.mkt_source, t.mkt_source) as mkt_source,
	coalesce(r.utm_campaign, c.utm_campaign, t.utm_campaign) as utm_campaign,
	coalesce(r.utm_content, c.utm_content, t.utm_content) as utm_content,
	coalesce(r.utm_term, c.utm_term, t.utm_term) as utm_term,
	sum(coalesce(r.leads, 0)) as leads,
	sum(coalesce(r.prospects, 0)) as prospects,
	sum(coalesce(r.qualifieds, 0)) as qualifieds,
	sum(coalesce(r.opportunities, 0)) as opportunities,
	sum(coalesce(r.first_listings, 0)) as first_listings,
	sum(coalesce(c.cost, 0)) as spent,
	sum(coalesce(t.budget,0)) as budget,
	sum(coalesce(t.prospects_target,0)) as prospects_target,
	sum(coalesce(t.qualifieds_target,0)) as qualifieds_target,
	sum(coalesce(t.opportunities_target,0)) as opportunities_target,
	sum(coalesce(t.first_listings_target,0)) as first_listings_target
from
	results r
	full outer join costs c
		on  r.date         = c.date
		and r.city_group   = c.city_group
		and r.mkt_origin   = c.mkt_origin
		and r.mkt_channel  = c.mkt_channel
		and r.mkt_medium   = c.mkt_medium
		and r.mkt_source   = c.mkt_source
		and r.utm_campaign = c.utm_campaign
		and r.utm_content  = c.utm_content
		and r.utm_term     = c.utm_term
	full outer join targets t
		on  r.date         = t.date
		and r.city_group   = t.city_group
		and r.mkt_origin   = t.mkt_origin
		and r.mkt_channel  = t.mkt_channel
		and r.mkt_medium   = t.mkt_medium
		and r.mkt_source   = t.mkt_source
		and r.utm_campaign = t.utm_campaign
		and r.utm_content  = t.utm_content
		and r.utm_term     = t.utm_term
	group by 1,2,3,4,5,6,7,8,9