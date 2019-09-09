with house_status as (
	-- merging of redundant house status records (subsequent status without sk_max_status_date, reasoned by minor status changes < 1 day)
	select
		fhs.sk_house_listing as sk_house,
		fhs.sk_region,
		fhs.status_history as status,
		min(fhs.sk_status_start_date) as sk_min_status_date,
		coalesce(to_char(to_date(nullif(fhs.sk_status_end_date,-1), 'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, to_char(current_date - 1, 'YYYYMMDD')::bigint) as sk_max_status_date
	from fact_house_listing_status fhs
	group by 1, 2, 3, 5
),
house_status_per_day as (
	-- create date series for each house and day in status publication
	--  ongoing listings = week_day = 0 (sunday)
	--  use daily status to filter listing_page_views that occured on not publicated listings (product/tracking bug)
	select
		hsp.sk_house,
		hsp.sk_region,
		hsp.status,
		hsp.sk_min_status_date,
		hsp.sk_max_status_date,
		dd.sk_date,
		dd.date,
		dd.week_day,
		dd.week_start
	from house_status hsp
	join dim_date dd on dd.sk_date between hsp.sk_min_status_date and sk_max_status_date
	where dd.date > date('2019-09-01')
),
fact_house_listings_unique as (
	select sk_house_listing, sk_partner from 
		(select sk_house_listing, sk_partner, row_number() over(partition by sk_house_listing order by sk_stranded_date desc) as rn_stranded 
		from fact_house_listings) 
		where rn_stranded = 1
),
house_status_and_dimensions as (
	-- returns all breakdowns for all listing versions for each day in publication
		select
		hsd.sk_date,
		hsd.date,
		hsd.week_day,
		hsd.week_start,
		hsd.sk_house,
       		dhl.id_house,
		hsd.status,
		dr.city_group,
	    dr.city_name as city,
	    dr.region_code,
	    dr.name as neighborhood,
	    date(date_trunc('week', dhl.ts_publication)) as week_start_publication,
	    case when dhl.house_bedrooms in (0,1) then 1
	     	 when dhl.house_bedrooms = 2 then 2
	     	 when dhl.house_bedrooms = 3 then 3
	     	 when dhl.house_bedrooms >= 4 then 4
	   	end as house_bedrooms,
		dhl.is_b2b,
		dp.sk_partner,
		dp.trade_name
	from house_status_per_day hsd
	join dim_region dr on dr.sk_region = hsd.sk_region
	join dim_house_listing dhl on hsd.sk_house = dhl.sk_house_listing
	left join fact_house_listings_unique fhlu on fhlu.sk_house_listing = dhl.sk_house_listing
	left join dim_partner dp on dp.sk_partner = fhlu .sk_partner
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
		count(distinct hsd.sk_house) as ongoing_listings
	from house_status_and_dimensions hsd
	where hsd.week_day = 0
	and hsd.status = 'publicado'
	group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
),
bookings as (
	-- returns number of bookings, independently of house status on booking_creation_date
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
		count(distinct flrf.sk_booking) as visits_booked
	from fact_listing_rent_flows flrf
	join house_status_and_dimensions hsd on hsd.sk_house = flrf.sk_house_listing and hsd.sk_date = flrf.sk_booking_created_date
	where flrf.sk_booking >= 0
	group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
),
lpv_events as (
	-- aggregates listing_page_view event counts per event date and house_id
	with amplitude as (
        select
            case when regexp_substr(e_house_id, '^\\d{9}$') != ''
                 then regexp_substr(e_house_id, '^\\d{9}$')::bigint
                 else null end as id_house,
            to_char(date(regexp_substr(event_time, '(\\d{4}-\\d{2}-\\d{2})')), 'YYYYMMDD')::bigint as sk_event_dt,
            regexp_substr(event_time, '(\\d{4}-\\d{2}-\\d{2})')::date as event_dt,
            uuid
        from datalake_clean.amplitude_events evt
        where et = 'listing_page_viewed'
            and ym >= '2018-01' and ym <= '2018-12'
            and app = '170698'
    union
    -- enriching with amplitude data via SPARK
        SELECT
            case when nullif(regexp_substr(event_house_id::varchar, '^\\d{9}$'), '') is not null
                 then regexp_substr(event_house_id::varchar, '^\\d{9}$')::bigint
                 else null end as id_house,
            to_char(date(regexp_substr(event_time, '(\\d{4}-\\d{2}-\\d{2})')), 'YYYYMMDD')::bigint as sk_event_dt,
            regexp_substr(event_time, '(\\d{4}-\\d{2}-\\d{2})')::date as event_dt,
            uuid
        FROM datalake_amplitude_clean_prod.listing_page_viewed_events
        WHERE app = 170698
            AND year >= 2019
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
		sum(le.cnt_listing_page_view) as listing_page_views
	from lpv_events le
	join house_status_and_dimensions hsd on hsd.id_house = le.id_house and hsd.sk_date = le.sk_event_dt
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
select * from results
;
