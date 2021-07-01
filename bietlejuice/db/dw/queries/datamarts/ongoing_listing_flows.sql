-- Query to identify flows in ongoing listings through weeks.
with
OL_week as (
-- Create query to identify weekly ongoing listings.
with
    fact as (
    select
        f.sk_house_listing,
        f.status_history,
        CASE
            WHEN dhl.is_b2b = TRUE THEN 'B2B'
            WHEN ciq.type_big_agent IS NOT NULL AND ciq.businesscontext='RENT' THEN 'CIQ'
            WHEN dhl.is_b2b = FALSE OR ciq.sk_house_listing IS NULL THEN 'Core'
        END AS is_b2b,
        d.date,
        d.week_start,
        d.weekday_name,
        d.month_start,
        d.month_end,
        row_number() over(partition by f.sk_house_listing, d.date order by nullif(f.ts_status_start,-1) desc) as order_status -- daily order status
    from fact_house_listing_status f
    join dim_date d
      on d.sk_date between nullif(f.sk_status_start_date,-1) and coalesce(to_char(to_date(nullif(sk_status_end_date,-1),'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, to_char(current_date -1, 'YYYYMMDD')::bigint)
    left join dim_house_listing dhl
      on dhl.sk_house_listing = f.sk_house_listing
    left join datamarts.quintoandar_consultant_listings ciq
        on f.sk_house_listing = ciq.sk_house_listing
    where f.status_history = 'publicado'
      and d.week_start >= '2018-12-31'
    ),
    fact_adjusted as (
    select
        fhs.sk_house_listing,
        fhs.date,
        fhs.week_start,
        fhs.weekday_name,
        fhs.month_start,
        fhs.month_end,
        fhs.order_status,
        fhs.status_history,
        fhs.is_b2b,
        dr.city_name,
        dr.city_group,
        dr.regional
    from fact fhs
    left join fact_house_listings fhl
      on fhs.sk_house_listing = fhl.sk_house_listing
    left join dim_region dr
      on fhl.sk_region = dr.sk_region
    ),
    OL as (
    select
    distinct
        week_start as week_start_ol,
        city_group as city_group_ol,
        city_name as city_name_ol,
        regional as regional_ol,
        status_history as status_history_ol,
        is_b2b as is_b2b_ol,
        sk_house_listing as sk_house_listing_ol
    from fact_adjusted
    where order_status = 1
      and weekday_name = 'Sunday'
    ),
    week_dates as (
    --Dates week_start and next_week
    select
        week_start,
        lead(week_start,1) over(order by week_start) as next_week
    from(
        select
            distinct
            week_start
        from dim_date
        where week_start <= current_date)
    )
    select
        OL.*,
        wd.next_week as next_week_ol
    from OL
    left join week_dates wd
      on OL.week_start_ol = wd.week_start
),
AL_week as (
-- Create query to identify weekly all listings.
with
    fact_AL as (
    select
        f.sk_house_listing,
        d.date,
        d.week_start,
        d.weekday_name,
        d.month_start,
        d.month_end,
        CASE
            WHEN dhl.is_b2b = TRUE THEN 'B2B'
            WHEN ciq.type_big_agent IS NOT NULL AND ciq.businesscontext='RENT' THEN 'CIQ'
            WHEN dhl.is_b2b = FALSE OR ciq.sk_house_listing IS NULL THEN 'Core'
        END AS is_b2b,
        f.status_history,
        case
            when status_history != 'suspenso' then status_history
            when (lower(status_change_reason) like '%reserv%' or lower(status_change_reason) like '%negocia%'
                or lower(status_change_reason) like '%proposta%') then 'suspended_in_negotiation'
            else 'suspended_other'
        end status_history_v2,
        row_number() over(partition by f.sk_house_listing, d.date order by nullif(f.ts_status_start,-1) desc) as order_status -- daily order status
    from fact_house_listing_status f
    join dim_date d
      on d.sk_date between nullif(f.sk_status_start_date,-1) and coalesce(to_char(to_date(nullif(sk_status_end_date,-1),'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, to_char(current_date -1, 'YYYYMMDD')::bigint)
    left join dim_house_listing dhl
      on dhl.sk_house_listing = f.sk_house_listing
    left join datamarts.quintoandar_consultant_listings ciq
        on f.sk_house_listing = ciq.sk_house_listing
    where d.week_start >= '2018-12-31'
    ),
    fact_adjusted_AL as (
    select
        fhsal.sk_house_listing,
        fhsal.date,
        fhsal.week_start,
        fhsal.weekday_name,
        fhsal.month_start,
        fhsal.month_end,
        fhsal.order_status,
        fhsal.is_b2b,
        fhsal.status_history,
        fhsal.status_history_v2,
        dr.city_name,
        dr.city_group,
        dr.regional
    from fact_AL fhsal
    left join fact_house_listings fhl
      on fhsal.sk_house_listing = fhl.sk_house_listing
    left join dim_region dr
      on fhl.sk_region = dr.sk_region
    )
    select
        faal.week_start as week_start_al,
        faal.week_start + interval '1 week' as next_week_al,
        faal.city_group as city_group_al,
        faal.city_name as city_name_al,
        faal.regional as regional_al,
        faal.sk_house_listing as sk_house_listing_al,
        faal.is_b2b as is_b2b_al,
        faal.status_history as status_history_al,
        faal.status_history_v2 as status_history_v2_al,
        dhl.listing_category_start as listing_category_start_al,
        cast(dhl.ts_listing_version_start as date) as listing_version_start_al
    from fact_adjusted_AL faal
    left join dim_house_listing dhl
      on faal.sk_house_listing = dhl.sk_house_listing
    where faal.order_status = 1 and faal.weekday_name = 'Sunday'
),
OL_AL_week as (
-- Query cross ongoing listing of current week and all listings of next week.
select
        ow.*,
        aw.*,
        ot.status_history_al as status_history_alo,
        ot.sk_house_listing_al as sk_house_listing_alo
        from OL_week ow
    full outer join AL_week aw
       on (ow.next_week_ol = aw.week_start_al
           and ow.sk_house_listing_ol = aw.sk_house_listing_al)
    left join AL_week ot
       on ot.next_week_al = aw.week_start_al
           and ot.sk_house_listing_al = aw.sk_house_listing_al
    	   and ot.status_history_al <> 'publicado'
),
ol_flows as (
-- Query to select distinct listings by status.
select
    week_start_ol,
    week_start_al,
    city_group_ol,
    city_group_al,
    city_name_ol,
    city_name_al,
    regional_ol,
    regional_al,
    is_b2b_ol,
    is_b2b_al,
    status_history_ol,
    status_history_al,
    status_history_v2_al,
    coalesce(status_history_ol,status_history_alo) as status_history_alo,
    listing_category_start_al,
    listing_version_start_al,
    count(distinct sk_house_listing_ol) as listings_ol,
    count(distinct sk_house_listing_al) as listings_al,
    count(distinct sk_house_listing_alo) as listings_alo
from OL_AL_week
group by
  week_start_ol,
  week_start_al,
  city_group_ol,
  city_group_al,
  city_name_ol,
  city_name_al,
  regional_ol,
  regional_al,
  is_b2b_ol,
  is_b2b_al,
  status_history_ol,
  status_history_al,
  status_history_v2_al,
  coalesce(status_history_ol, status_history_alo),
  listing_category_start_al,
  listing_version_start_al
order by
  week_start_ol,
  week_start_al
),
week_flows as (
-- Query to build the calculation base for ongoing listing flow by week.
select
	date(least(week_start_ol,(week_start_al - interval '1 week'))) as week_start,
	coalesce(city_name_ol,city_name_al) as city_name,
	coalesce(city_group_ol,city_group_al) as city_group,
	coalesce(regional_ol,regional_al) as regional,
	coalesce(is_b2b_ol,is_b2b_al) as is_b2b,
	sum(listings_ol) as ol_week,
	sum(case when status_history_ol = 'publicado' and (status_history_al not in ('publicado','suspenso', 'alugado') or status_history_al is null)
		then listings_ol end) as ol_unpublished,
	sum(case when status_history_ol = 'publicado' and status_history_al = 'suspenso' then listings_al end) as ol_suspended,
	sum(case when status_history_ol = 'publicado' and status_history_al = 'alugado' then listings_al end) as ol_rented,
	sum(case when status_history_ol is null
				  and status_history_al = 'publicado'
				  and (listing_version_start_al >= date(least(week_start_ol,(week_start_al - interval '1 week')) + interval '1 week') and
				  	   listing_version_start_al < date(least(week_start_ol,(week_start_al - interval '1 week')) + interval '2 week'))
				  and listing_category_start_al = 'First Listing'
				  then listings_al end) as al_new_first_listing,
	sum(case when status_history_ol is null
				  and status_history_al = 'publicado'
				  and (listing_version_start_al >= date(least(week_start_ol,(week_start_al - interval '1 week')) + interval '1 week') and
				  	   listing_version_start_al < date(least(week_start_ol,(week_start_al - interval '1 week')) + interval '2 week'))
				  and listing_category_start_al = 'Re-Listing'
				  then listings_al end) as al_new_re_listing,
	sum(case when status_history_ol is null
				  and status_history_al = 'publicado'
				  and (listing_version_start_al >= date(least(week_start_ol,(week_start_al - interval '1 week')) + interval '1 week') and
				  	   listing_version_start_al < date(least(week_start_ol,(week_start_al - interval '1 week')) + interval '2 week'))
				  and listing_category_start_al = 'Recovered'
				  then listings_al end) as al_new_recovered,
	sum(case when status_history_ol is null
				  and status_history_al = 'publicado'
				  and (listing_version_start_al >= date(least(week_start_ol,(week_start_al - interval '1 week')) + interval '1 week') and
				  	   listing_version_start_al < date(least(week_start_ol,(week_start_al - interval '1 week')) + interval '2 week'))
				  then listings_al end) as al_new_published,
	sum(case when status_history_ol is null and status_history_al = 'publicado' then listings_al end) as al_published,
	sum(case when status_history_al = 'publicado'
				  and status_history_alo = 'despublicado'
				  then listings_al end) as al_unpublished_to_published,
	sum(case when status_history_al = 'publicado'
				  and status_history_alo = 'suspenso'
				  then listings_al end) as al_suspended_to_published,
	sum(case when status_history_al = 'publicado'
				  and status_history_alo in ('edicao', 'aguardando_publicacao')
				  then listings_al end) as al_other_listings,
	sum(case when status_history_al = 'publicado' then listings_al end) as ol_next_week,
	date(least(week_start_ol,(week_start_al - interval '1 week')) + interval '1 week') as next_week_start,
  sum(case
          when status_history_ol = 'publicado'
          and status_history_v2_al = 'suspended_in_negotiation' then listings_al
      end) as ol_suspended_in_negotiation
from ol_flows
group by
  date(least(week_start_ol,(week_start_al - interval '1 week'))),
  coalesce(city_name_ol, city_name_al),
  coalesce(city_group_ol, city_group_al),
  coalesce(regional_ol, regional_al),
  coalesce(is_b2b_ol,is_b2b_al),
  date(least(week_start_ol,(week_start_al - interval '1 week')) + interval '1 week')
order by
  date(least(week_start_ol,(week_start_al - interval '1 week'))) desc,
  date(least(week_start_ol,(week_start_al - interval '1 week')) + interval '1 week') desc
)
select
-- Query to calculate the ongoing listing flow by week.
	wf.week_start,
	wf.city_group,
	wf.city_name,
	wf.regional,
	wf.is_b2b,
	sum(coalesce(wf.ol_week,0)) as ol_week,
	sum(coalesce(wf.ol_unpublished,0)) as ol_unpublished,
	sum(coalesce(wf.ol_suspended,0)) as ol_suspended,
	sum(coalesce(wf.ol_rented,0)) as ol_rented,
	sum(coalesce(wf.al_new_first_listing,0)) as new_first_listing,
	sum(coalesce(wf.al_new_re_listing,0)) as new_re_listing,
	sum(coalesce(wf.al_new_recovered,0)) as new_recovered,
	sum(coalesce(wf.al_unpublished_to_published,0)) as unpublished_to_published,
	sum(coalesce(wf.al_suspended_to_published,0)) as suspended_to_published,
	sum(coalesce(wf.al_other_listings,0)) as other_listings,
	sum(coalesce(wf.ol_next_week,0)) as ol_next_week,
	wf.next_week_start,
  sum(coalesce(wf.ol_suspended_in_negotiation, 0)) as ol_suspended_in_negotiation,
  current_timestamp as ts_load
from week_flows wf
where wf.week_start < date_trunc('week',current_date) - interval '1 week'
group by
  wf.week_start,
  wf.city_group,
  wf.city_name,
  wf.regional,
  wf.is_b2b,
  wf.next_week_start
order by
  wf.week_start desc