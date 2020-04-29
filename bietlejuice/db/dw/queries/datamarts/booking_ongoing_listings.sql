with
daily_published_listings as (
select
    f.sk_house_listing,
    f.status_history,
    d.sk_date,
    d.date,
    d.week_start,
    d.week_day,
    d.weekday_name,
    d.month_start,
    d.month_end,
    row_number() over(partition by f.sk_house_listing, d.date order by f.ts_status_start desc) as order_status -- daily order status
from fact_house_listing_status f
join dim_date d
  on d.sk_date between nullif(f.sk_status_start_date,-1) and coalesce(to_char(to_date(nullif(sk_status_end_date,-1),'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, to_char(current_date -1, 'YYYYMMDD')::bigint)
where f.status_history = 'publicado' -- consider only published status
  and substring(sk_house_listing,10,12) <> '000' -- consider only listings that already started publication
),
house_status_and_dimensions as (
select
    fhs.sk_date,
    fhs.sk_house_listing,
    fhs.date,
    fhs.week_day,
    fhs.week_start,
    fhs.weekday_name,
    dhl.id_house,
    fhs.month_start,
    fhs.month_end,
    fhs.order_status,
    fhs.status_history,
    fhl.sk_region,
    dr.city_group,
    dr.city_name as city,
    dr.region_code,
    dr.name as neighborhood,
    date(date_trunc('week', dhl.ts_publication)) as week_start_publication,
    case
        when dhl.house_bedrooms in (0,1) then 1
        when dhl.house_bedrooms = 2 then 2
        when dhl.house_bedrooms = 3 then 3
        when dhl.house_bedrooms >= 4 then 4
    end as house_bedrooms,
    dhl.is_b2b,
    dp.sk_partner,
    dp.trade_name
from daily_published_listings fhs
left join fact_house_listings fhl
  on fhs.sk_house_listing = fhl.sk_house_listing
left join dim_region dr
  on fhl.sk_region = dr.sk_region
left join dim_house_listing dhl
  on fhs.sk_house_listing = dhl.sk_house_listing
left join dim_partner dp
  on dp.sk_partner = fhl.sk_partner
where fhs.order_status = 1
  and dr.city_group is not null
  and fhs.weekday_name = 'Sunday'
),
house_status_and_dimensions_book as (
select
    fhs.sk_date,
    fhs.sk_house_listing,
    fhs.date,
    fhs.week_day,
    fhs.week_start,
    fhs.weekday_name,
    dhl.id_house,
    fhs.month_start,
    fhs.month_end,
    fhs.order_status,
    fhs.status_history,
    fhl.sk_region,
    dr.city_group,
    dr.city_name as city,
    dr.region_code,
    dr.name as neighborhood,
    date(date_trunc('week', dhl.ts_publication)) as week_start_publication,
    case
        when dhl.house_bedrooms in (0,1) then 1
        when dhl.house_bedrooms = 2 then 2
        when dhl.house_bedrooms = 3 then 3
        when dhl.house_bedrooms >= 4 then 4
    end as house_bedrooms,
    dhl.is_b2b,
    dp.sk_partner,
    dp.trade_name
from daily_published_listings fhs
join fact_house_listings fhl
  on fhs.sk_house_listing = fhl.sk_house_listing
join dim_region dr
  on fhl.sk_region = dr.sk_region
left join dim_house_listing dhl
  on fhs.sk_house_listing = dhl.sk_house_listing
left join dim_partner dp
  on dp.sk_partner = fhl.sk_partner
where fhs.order_status = 1
  and dr.city_group is not null
),
ongoing_listings_wk_snapshot as (
	-- returns for each week and dimension the sunday count/snapshot of publicated listings
	select
	    hsd.city_group,
	    hsd.city,
	    hsd.region_code,
	    hsd.neighborhood,
	    hsd.week_start,
	    hsd.week_start_publication,
	    hsd.house_bedrooms,
		hsd.is_b2b,
		hsd.sk_partner,
		hsd.trade_name,
		count(distinct hsd.sk_house_listing) as ongoing_listings
	from house_status_and_dimensions hsd
	group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
),
bookings as (
	-- returns number of bookings, independently of house status on booking_creation_date
	select
		hsdb.city_group,
		hsdb.city,
		hsdb.region_code,
		hsdb.neighborhood,
	    hsdb.week_start,
	    hsdb.week_start_publication,
	    hsdb.house_bedrooms,
		hsdb.is_b2b,
		hsdb.sk_partner,
		hsdb.trade_name,
		count(distinct flrf.sk_booking) as visits_booked
	from fact_listing_rent_flows flrf
	join house_status_and_dimensions_book hsdb on hsdb.sk_house_listing = flrf.sk_house_listing and hsdb.sk_date = flrf.sk_booking_created_date
	where flrf.sk_booking >= 0
	group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
),
lpv_events as (
	-- aggregates listing_page_view event counts per event date and house_id
    with amplitude as (
        select
            case
              when nullif(regexp_substr(json_extract_path_text(event_properties, 'house_id'), '^\\d{9}$'), '') is not null
                then regexp_substr(json_extract_path_text(event_properties, 'house_id'), '^\\d{9}$')::bigint
              else null
            end as id_house,
            to_char(date(ts_event), 'YYYYMMDD')::bigint as sk_event_dt,
            ts_event::date as event_dt,
            uuid
        from datalake_amplitude_clean_staging_prod."170698_listing_page_viewed_events"
    )
    select
        id_house,
        sk_event_dt,
        event_dt,
        count(distinct uuid) as cnt_listing_page_view
    from amplitude
    group by 1,2,3
),
listing_page_views as (
	-- returns number of listing_page_view events per house and date, independently of house status on event date
	select
		hsdb.city_group,
		hsdb.city,
		hsdb.region_code,
		hsdb.neighborhood,
	    hsdb.week_start,
	    hsdb.week_start_publication,
	    hsdb.house_bedrooms,
		hsdb.is_b2b,
		hsdb.sk_partner,
		hsdb.trade_name,
		sum(le.cnt_listing_page_view) as listing_page_views
	from lpv_events le
	join house_status_and_dimensions_book hsdb on hsdb.id_house = le.id_house and hsdb.sk_date = le.sk_event_dt
	group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
),
results as (
	-- merge results from different sub-queries into one result set
	select
   		coalesce(ol.city_group, coalesce(vb.city_group, lpv.city_group)) as "city_group",
		coalesce(ol.city, coalesce(vb.city, lpv.city)) as "city",
		coalesce(ol.region_code, coalesce(vb.region_code, lpv.region_code)) as "region_code",
		coalesce(ol.neighborhood, coalesce(vb.neighborhood, lpv.neighborhood)) as "neighborhood",
	    coalesce(ol.week_start, coalesce(vb.week_start, lpv.week_start)) as "week_start",
		coalesce(ol.week_start_publication, coalesce(vb.week_start_publication, lpv.week_start_publication)) as "week_start_publication",
		coalesce(ol.house_bedrooms, coalesce(vb.house_bedrooms, lpv.house_bedrooms)) as "house_bedrooms",
		coalesce(ol.is_b2b, coalesce(vb.is_b2b, lpv.is_b2b)) as "is_b2b",
		coalesce(ol.sk_partner, coalesce(vb.sk_partner, lpv.sk_partner)) as "sk_partner",
		coalesce(ol.trade_name, coalesce(vb.trade_name, lpv.trade_name)) as "trade_name",
		ongoing_listings,
		visits_booked,
		listing_page_views
	from ongoing_listings_wk_snapshot ol
	full join bookings vb on
	    vb.city_group = ol.city_group and
	    vb.city = ol.city and
		vb.region_code = ol.region_code and
		vb.neighborhood = ol.neighborhood and
	    vb.week_start = ol.week_start and
		vb.week_start_publication = ol.week_start_publication and
		vb.house_bedrooms = ol.house_bedrooms and
		vb.is_b2b = ol.is_b2b and
		vb.sk_partner = ol.sk_partner and
		vb.trade_name = ol.trade_name
	full join listing_page_views lpv on
	    lpv.city_group = ol.city_group and
	    lpv.city = ol.city and
		lpv.region_code = ol.region_code and
		lpv.neighborhood = ol.neighborhood and
	    lpv.week_start = ol.week_start and
		lpv.week_start_publication = ol.week_start_publication and
		lpv.house_bedrooms = ol.house_bedrooms and
		lpv.is_b2b = ol.is_b2b and
		lpv.sk_partner = ol.sk_partner and
		lpv.trade_name = ol.trade_name
	order by 5, 6, 1, 2, 3, 4, 7, 8, 9, 10
)
select
  *,
  current_timestamp as ts_load
from results
