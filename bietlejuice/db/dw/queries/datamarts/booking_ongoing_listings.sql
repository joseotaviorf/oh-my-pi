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
	count(distinct case when status_history = 'publicado' then sk_house end) as "ongoing_listings"
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
FROM fact_house_status fhs
join dim_date dd 
  on dd.sk_date between fhs.sk_min_status_date and coalesce(to_char(to_date(fhs.sk_max_status_date, 'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, to_char(current_date - 1, 'YYYYMMDD')::bigint)
left join dim_region dr 
     using(sk_region)
left join dim_house_listing dh 
  on fhs.sk_house = dh.sk_house_listing
where dd.weekday_name = 'Sunday'
)
where 1=1 --rk = 1
  and week_start >= '2018-01-01'
group by 1, 2, 3, 4, 5, 6, 7, 8
having count(distinct case when status_history = 'publicado' then sk_house end) > 0
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
WHERE 1=1
  and ddb.week_start >= '2018-01-01'
GROUP BY 1,2,3,4,5,6,7,8
ORDER BY 5 DESC
)
SELECT 
    coalesce(ol.city_group, vb.city_group) as "city_group",
	coalesce(ol.city, vb.city) as "city",
	coalesce(ol.macro_region, vb.macro_region) as "macro_region",
	coalesce(ol.neighborhood, vb.neighborhood) as "neighborhood",
    coalesce(ol.week_start, vb.week_start) as "week_start",
	coalesce(ol.week_start_publication, vb.week_start_publication) as "week_start_publication",
	coalesce(ol.house_bedrooms, vb.house_bedrooms) as "house_bedrooms",
	coalesce(ol.is_b2b, vb.is_b2b) as "is_b2b",
	ongoing_listings,
	visits_booked
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
ORDER BY 5, 6, 1, 2, 3, 4, 7, 8
