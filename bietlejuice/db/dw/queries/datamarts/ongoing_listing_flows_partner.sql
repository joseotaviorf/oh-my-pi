-- Query to identify flows in ongoing listings through weeks.
with
OL_week as (
-- Create query to identify weekly ongoing listings.
with
    fact as (
    select
        f.sk_house_listing,
        f.status_history,
        fhl.sk_partner,
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
    left join fact_house_listings fhl
      on fhl.sk_house_listing = f.sk_house_listing
    where f.status_history = 'publicado'
      and d.week_start >= '2018-12-31'
      and dhl.is_b2b = True
    ),
    fact_adjusted as (
    select
        fhs.sk_house_listing,
        fhs.date,
        fhs.sk_partner,
        fhs.week_start,
        fhs.weekday_name,
        fhs.month_start,
        fhs.month_end,
        fhs.order_status,
        fhs.status_history
    from fact fhs
    left join fact_house_listings fhl
      on fhs.sk_house_listing = fhl.sk_house_listing
   ),
    OL as (
    select
    distinct
        week_start as week_start_ol,
        sk_partner as sk_partner_ol,
        status_history as status_history_ol,
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
        fhl.sk_partner,
        d.week_start,
        d.weekday_name,
        d.month_start,
        d.month_end,
        f.status_history,
        row_number() over(partition by f.sk_house_listing, d.date order by nullif(f.ts_status_start,-1) desc) as order_status -- daily order status
    from fact_house_listing_status f
    join dim_date d
      on d.sk_date between nullif(f.sk_status_start_date,-1) and coalesce(to_char(to_date(nullif(sk_status_end_date,-1),'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, to_char(current_date -1, 'YYYYMMDD')::bigint)
    left join dim_house_listing dhl
      on dhl.sk_house_listing = f.sk_house_listing
    left join fact_house_listings fhl
      on fhl.sk_house_listing = f.sk_house_listing
    where d.week_start >= '2018-12-31'
          and dhl.is_b2b = True
    ),
    fact_adjusted_AL as (
    select
        fhsal.sk_house_listing,
        fhsal.date,
        fhsal.sk_partner,
        fhsal.week_start,
        fhsal.weekday_name,
        fhsal.month_start,
        fhsal.month_end,
        fhsal.order_status,
        fhsal.status_history
    from fact_AL fhsal
    left join fact_house_listings fhl
      on fhsal.sk_house_listing = fhl.sk_house_listing
    )
    select
        faal.week_start as week_start_al,
        faal.week_start + interval '1 week' as next_week_al,
        faal.sk_partner as sk_partner_al,
        faal.sk_house_listing as sk_house_listing_al,
        faal.status_history as status_history_al,
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
    sk_partner_ol,
    sk_partner_al,
    status_history_ol,
    status_history_al,
    coalesce(status_history_ol,status_history_alo) as status_history_alo,
    listing_category_start_al,
    listing_version_start_al,
    count(distinct sk_house_listing_ol) as listings_ol,
    count(distinct sk_house_listing_al) as listings_al,
    count(distinct sk_house_listing_alo) as listings_alo
from OL_AL_week
group by 1,2,3,4,5,6,7,8,9
order by 1,2
),
week_flows as (
-- Query to build the calculation base for ongoing listing flow by week.
select
	date(least(week_start_ol,(week_start_al - interval '1 week'))) as week_start,
	coalesce(sk_partner_ol,sk_partner_al) as sk_partner,
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
	date(least(week_start_ol,(week_start_al - interval '1 week')) + interval '1 week') as next_week_start
from ol_flows
group by 1,2,16
order by 1 desc, 16 desc
)
select
-- Query to calculate the ongoing listing flow by week.
	wf.week_start,
	wf.sk_partner,
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
  current_timestamp as ts_load
from week_flows wf
where wf.week_start < date_trunc('week',current_date) - interval '1 week'
group by 1,2,14
order by 1 desc
