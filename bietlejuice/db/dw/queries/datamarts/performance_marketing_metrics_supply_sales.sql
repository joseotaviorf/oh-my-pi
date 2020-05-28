with
leads as (
  select
    sk_lead_date as dt,
    coalesce(dr.city_group, '') as city_group,
    f.mkt_origin,
    f.mkt_channel,
    count(1) as daily_leads
  from
    sale.fact_listing_flows f
    join dim_region dr
      on f.sk_region = dr.sk_region
  where
    f.mkt_origin in ('Price Calculator', 'Owner PWA')
    and f.sk_lead_date>=20191001
  group by 1, 2, 3, 4
  ),
prospects as (
  select
    sk_prospect_date as dt,
    coalesce(dr.city_group, '') as city_group,
    f.mkt_origin,
    f.mkt_channel,
    count(1) as daily_prospects
  from
    sale.fact_listing_flows f
    join dim_region dr
      on f.sk_region = dr.sk_region
  where
    f.mkt_origin in ('Price Calculator', 'Owner PWA')
    and f.sk_lead_date>=20191001
  group by 1, 2, 3, 4
  ),
qualifieds as (
  select
    sk_qualified_date as dt,
    coalesce(dr.city_group, '') as city_group,
    f.mkt_origin,
    f.mkt_channel,
    count(1) as daily_qualifieds
    from
    sale.fact_listing_flows f
      join dim_region dr
        on f.sk_region = dr.sk_region
  where
    f.mkt_origin in ('Price Calculator', 'Owner PWA')
    and f.sk_lead_date>=20191001
    group by 1, 2, 3, 4
  ),
opportunities as (
  select
    sk_opportunity_date as dt,
    coalesce(dr.city_group, '') as city_group,
    f.mkt_origin,
    f.mkt_channel,
    count(1) as daily_opportunities
  from
    sale.fact_listing_flows f
    join dim_region dr
      on f.sk_region = dr.sk_region
  where
    f.mkt_origin in ('Price Calculator', 'Owner PWA')
    and f.sk_lead_date>=20191001
  group by 1, 2, 3, 4
  ),
listings as (
  select
    sk_first_listing_date as dt,
    coalesce(dr.city_group, '') as city_group,
    f.mkt_origin,
    f.mkt_channel,
    count(1) as daily_listings
  from
    sale.fact_listing_flows f
    join dim_region dr
      on f.sk_region = dr.sk_region
  where
    f.mkt_origin in ('Price Calculator', 'Owner PWA')
    and f.sk_lead_date>=20191001
  group by 1, 2, 3, 4
  ),
temp_res as (
  select
    coalesce(l.dt,p.dt,q.dt,o.dt,t.dt) as dt,
    coalesce(l.city_group,p.city_group,q.city_group,o.city_group,t.city_group) as city_group,
    coalesce(l.mkt_origin,p.mkt_origin,q.mkt_origin,o.mkt_origin,t.mkt_origin) as mkt_origin,
    coalesce(l.mkt_channel,p.mkt_channel,q.mkt_channel,o.mkt_channel,t.mkt_channel) as mkt_channel,
    coalesce(l.daily_leads,0) as daily_leads,
    coalesce(p.daily_prospects,0) as daily_prospects,
    coalesce(q.daily_qualifieds,0) as daily_qualifieds,
    coalesce(o.daily_opportunities,0) as daily_opportunities,
    coalesce(t.daily_listings,0) as daily_listings
  from leads l
  full outer join opportunities o
    on  l.dt = o.dt
    and l.city_group = o.city_group
    and l.mkt_channel = o.mkt_channel
    and l.mkt_origin = o.mkt_origin
  full outer join qualifieds q
    on  l.dt = q.dt
    and l.city_group = q.city_group
    and l.mkt_channel = q.mkt_channel
    and l.mkt_origin = q.mkt_origin
  full outer join prospects p
    on  l.dt = p.dt
    and l.city_group = p.city_group
    and l.mkt_channel = p.mkt_channel
    and l.mkt_origin = p.mkt_origin
  full outer join listings t
    on  l.dt = t.dt
    and l.city_group = t.city_group
    and l.mkt_channel = t.mkt_channel
    and l.mkt_origin = t.mkt_origin
  ),
dim_dt as (
  select distinct
    sk_date as dt
  from
    dim_date
  where
    date between date('2019-10-01') and current_date
  ),
dim_city_group as (
  select distinct
    coalesce(city_group, '') as city_group
  from
    dim_region
  ),
dim_growth_taxonomy as (
  select distinct
    mkt_origin,
    mkt_channel
  from
    temp_res
  ),
dim_supply_distinct as (
  select
  dt,
  city_group,
  mkt_origin,
  mkt_channel
  from
    dim_dt,
    dim_city_group,
    dim_growth_taxonomy
  ),
supply_daily_funnel_counts as(
  select
    date(dst.dt) as date,
    dst.city_group,
    dst.mkt_origin,
    dst.mkt_channel as mkt_channel,
    sum(coalesce(tr.daily_leads, 0)) as leads,
    sum(coalesce(tr.daily_prospects, 0)) as prospects,
    sum(coalesce(tr.daily_qualifieds, 0)) as qualifieds,
    sum(coalesce(tr.daily_opportunities, 0)) as opportunities,
    sum(coalesce(tr.daily_listings, 0)) as first_listings
  from
    dim_supply_distinct dst
    left join temp_res tr
      on  dst.dt = tr.dt
      and dst.city_group = tr.city_group
      and dst.mkt_channel = tr.mkt_channel
      and dst.mkt_origin = tr.mkt_origin
  group by 1, 2, 3, 4
  ),
supply_daily_spent as (
  select
    date(co.sk_date) date,
    co.city_group,
    replace(co.mkt_origin, ' - Sale', '') as mkt_origin,
    co.mkt_channel,
    sum(co.cost) as spent
  from
    marketing.fact_marketing_daily_costs co
  where
    co.mkt_origin in ('Price Calculator - Sale', 'Owner PWA - Sale')
    and co.funnel_side = 'supply'
  group by 1, 2, 3, 4
  )
select
  coalesce(sdc.date, sdf.date) as date,
  coalesce(sdc.city_group, sdf.city_group) as city_group,
  coalesce(sdc.mkt_origin, sdf.mkt_origin) as mkt_origin,
  coalesce(sdc.mkt_channel, sdf.mkt_channel) as mkt_channel,
  sum(coalesce(sdc.spent, 0)) as spent,
  sum(coalesce(sdf.leads, 0)) as leads,
  sum(coalesce(sdf.prospects, 0)) as prospects,
  sum(coalesce(sdf.qualifieds, 0)) as qualifieds,
  sum(coalesce(sdf.opportunities, 0)) as opportunities,
  sum(coalesce(sdf.first_listings, 0)) as listings
from
  supply_daily_spent sdc
  full outer join supply_daily_funnel_counts sdf
    on  sdc."date" = sdf."date"
    and sdc.city_group = sdf.city_group
    and sdc.mkt_channel = sdf.mkt_channel
    and sdc.mkt_origin = sdf.mkt_origin
group by 1,2,3,4
having (
  sum(coalesce(sdc.spent, 0)) > 0
  or sum(coalesce(sdf.leads, 0)) > 0
  or sum(coalesce(sdf.prospects, 0)) > 0
  or sum(coalesce(sdf.qualifieds, 0)) > 0
  or sum(coalesce(sdf.opportunities, 0)) > 0
  or sum(coalesce(sdf.first_listings, 0)) > 0
)