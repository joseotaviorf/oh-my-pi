with ol as (
	select
		city_group,
		city,
		macro_region,
		neighborhood,
	    week_start,
		to_date(week_start_publication,'YYYY-MM-DD') as week_start_publication,
		case when house_bedrooms in (0,1) then 1
		     when house_bedrooms = 2 then 2
		     when house_bedrooms = 3 then 3
		     when house_bedrooms >= 4 then 4
		     end as house_bedrooms,
		is_b2b,
		count(distinct case when status_history = 'publicado' then sk_house_listing end) as "ongoing_listings"
		from(
	SELECT
	    fhs.*,
	    dr.city_group,
	    dr.city_name as city,
	    dr.macro_name as macro_region,
	    dr.name as neighborhood,
	    dd.date,
	    dd.weekday_name,
	    dd.week_start,
	    dh.is_b2b,
	    dh.is_last_version,
	    dh.ts_publication,
	    dh.house_bedrooms,
	    date_trunc('week',dh.ts_publication) as week_start_publication
	FROM fact_house_listing_status fhs
	join dim_date dd
	  on dd.sk_date between nullif(fhs.sk_status_start_date,-1) and coalesce(to_char(to_date(nullif(fhs.sk_status_end_date,-1), 'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, to_char(current_date - 1, 'YYYYMMDD')::bigint)
	left join dim_region dr
	     using(sk_region)
	left join dim_house_listing dh
	  on fhs.sk_house_listing = dh.sk_house_listing
	where dd.weekday_name = 'Sunday'
	)
	where week_start >= '2018-01-01'
	group by 1, 2, 3, 4, 5, 6, 7, 8
	having count(distinct case when status_history = 'publicado' then sk_house_listing end) > 0
	order by 2 desc, 1 asc, 3 desc, 4
),
vb as (
	SELECT
	    dr.city_group,
	    dr.city_name as city,
	    dr.macro_name as macro_region,
	    dr.name as neighborhood,
	    ddb.week_start,
	    dd.week_start as "Week_start_publication",
		case when house_bedrooms in (0,1) then 1
		     when house_bedrooms = 2 then 2
		     when house_bedrooms = 3 then 3
		     when house_bedrooms >= 4 then 4
		     end as house_bedrooms,
	    dh.is_b2b,
	    COUNT(DISTINCT CASE WHEN (fr.sk_booking  >= 0) THEN fr.sk_booking  ELSE NULL END) AS "visits_booked"
	FROM fact_listing_rent_flows fr
	FULL OUTER JOIN dim_house_listing dh
	    ON fr.sk_house_listing = dh.sk_house_listing
	LEFT JOIN fact_house_listings fh
	    ON fh.sk_house_listing = dh.sk_house_listing
	LEFT JOIN dim_region  dr
	    ON fh.sk_region = dr.sk_region
	LEFT JOIN dim_date ddb
	    ON fr.sk_booking_created_date = ddb.sk_date
	LEFT JOIN dim_date dd
	    ON (DATE(dd.date )) = (DATE(dh.ts_publication ))
	WHERE ddb.week_start >= '2018-01-01'
	GROUP BY 1,2,3,4,5,6,7,8
	ORDER BY 5 DESC
),
lpv_events as (
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
listing_dimensions as (
	select
	dhl.id_house,
	dhl.sk_house_listing,
	coalesce(dhl.ts_listing_version_start, dhl.ts_publication) as ts_listing_version_start_mod,
	coalesce(dhl.ts_listing_version_end, CURRENT_TIMESTAMP) as ts_listing_version_end_mod,
	dhl.ts_publication,
	dhl.ts_last_de_publication,
	dr.city_group,
    dr.city_name as city,
    dr.macro_name as macro_region,
    dr.name as neighborhood,
    case when dhl.house_bedrooms in (0,1) then 1
	     when dhl.house_bedrooms = 2 then 2
	     when dhl.house_bedrooms = 3 then 3
	     when dhl.house_bedrooms >= 4 then 4
	     end as house_bedrooms,
    dhl.is_b2b
	from dim_house_listing dhl
	join fact_house_listings fhl on fhl.sk_house_listing = dhl.sk_house_listing
	join dim_region dr on fhl.sk_region = dr.sk_region
),
lpv as (
	select
	ld.city_group,
    ld.city,
    ld.macro_region,
    ld.neighborhood,
    date_trunc('week', le.event_dt) as week_start,
    date_trunc('week', ld.ts_publication) as week_start_publication,
	ld.house_bedrooms,
    ld.is_b2b,
	sum(le.cnt_listing_page_view) as listing_page_views
	from lpv_events le
	join listing_dimensions ld on
		ld.id_house = le.id_house and
		le.event_dt between ld.ts_listing_version_start_mod and ts_listing_version_end_mod
	where le.event_dt >= date('2018-01-01')
	group by 1, 2, 3, 4, 5, 6, 7, 8
)
SELECT
    coalesce(ol.city_group, coalesce(vb.city_group, lpv.city_group)) as "city_group",
	coalesce(ol.city, coalesce(vb.city, lpv.city)) as "city",
	coalesce(ol.macro_region, coalesce(vb.macro_region, lpv.macro_region)) as "macro_region",
	coalesce(ol.neighborhood, coalesce(vb.neighborhood, lpv.neighborhood)) as "neighborhood",
    coalesce(ol.week_start, coalesce(vb.week_start, lpv.week_start)) as "week_start",
	coalesce(ol.week_start_publication, coalesce(vb.week_start_publication, lpv.week_start_publication)) as "week_start_publication",
	coalesce(ol.house_bedrooms, coalesce(vb.house_bedrooms, lpv.house_bedrooms)) as "house_bedrooms",
	coalesce(ol.is_b2b, coalesce(vb.is_b2b, lpv.is_b2b)) as "is_b2b",
	ongoing_listings,
	visits_booked,
	listing_page_views,
	current_timestamp as ts_load
FROM ol
FULL JOIN vb ON
    vb.city_group = ol.city_group and
    vb.city = ol.city and
	vb.macro_region = ol.macro_region and
	vb.neighborhood = ol.neighborhood and
    vb.week_start = ol.week_start and
	vb.week_start_publication = ol.week_start_publication and
	vb.house_bedrooms = ol.house_bedrooms and
	vb.is_b2b = ol.is_b2b
FULL JOIN lpv ON
    lpv.city_group = ol.city_group and
    lpv.city = ol.city and
	lpv.macro_region = ol.macro_region and
	lpv.neighborhood = ol.neighborhood and
    lpv.week_start = ol.week_start and
	lpv.week_start_publication = ol.week_start_publication and
	lpv.house_bedrooms = ol.house_bedrooms and
	lpv.is_b2b = ol.is_b2b
ORDER BY 5, 6, 1, 2, 3, 4, 7, 8
