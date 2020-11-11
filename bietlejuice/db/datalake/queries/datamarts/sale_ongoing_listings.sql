with house_listing_status as (
	with sale_listing_aud as (
		select 
			lbc.id_listing_business_context as id,
			lbc.id_house,
			lbc.rev,
			from_unixtime(cast(rev.ts_revision as bigint)/1000) as ts_rev_time, -- datetime revision started
			lbc.status,
			lag(lbc.status) over(partition by lbc.id_listing_business_context order by lbc.rev) as previous_status -- previous status ordered by the datetime that happened
		from datalake_ebdb_clean_prod.listing_business_context_aud lbc
		join datalake_ebdb_clean_prod.user_revision_entity rev 
			on rev.id = lbc.rev  
		where lbc.business_context = 'SALE'
		)
		, house_status_history as (
		select 
			sla.id,
			sla.id_house,
			cast(sla.ts_rev_time as timestamp) as ts_status_changed,
			sla.status as status_history,
			lead(sla.ts_rev_time) over(partition by sla.id order by sla.rev) as ts_next_status_change_time,
			row_number() over(partition by sla.id order by sla.rev) as order_status
		from sale_listing_aud sla
		where 
			sla.status <> sla.previous_status 
			or sla.previous_status is null
	)
select 
	id,
	id_house,
	status_history,
	cast(ts_status_changed as timestamp) as ts_status_start,
	ts_next_status_change_time as ts_status_end
from house_status_history
)
, fact_house_status as (
select
  	hls.id_house as id_house,
	hls.ts_status_start,
  	hls.ts_status_end,
  	coalesce(CAST(REPLACE(SUBSTRING(CAST(hls.ts_status_start AS VARCHAR), 1, 10), '-', '') AS BIGINT), -1) AS sk_status_start_date,
  	coalesce(CAST(REPLACE(SUBSTRING(CAST(hls.ts_status_end AS VARCHAR), 1, 10), '-', '') AS BIGINT), -1) AS sk_status_end_date,
 	hls.status_history
from house_listing_status hls
)
, daily_published_listings as (
select
    	f.id_house,
    	f.status_history,
    	d.date,
    	d.week_start,
    	d.weekday_name,
    	f.sk_status_start_date,
    	f.sk_status_end_date,
    	row_number() over(partition by f.id_house, d.date order by f.ts_status_start desc) as order_status -- daily order status
from fact_house_status f
join datalake_clean.ods_dim_date d
    on CAST(d.sk_date AS BIGINT) BETWEEN NULLIF(f.sk_status_start_date,-1) 
    and coalesce(NULLIF(sk_status_end_date, -1), CAST(REPLACE(CAST(current_date AS VARCHAR), '-', '') AS BIGINT) - 1)
where f.status_history = 'PUBLISHED'
)
, daily_published_listings_with_region as (
select
    fhs.id_house,
    fhs.date,
    fhs.week_start,
    fhs.weekday_name,
    fhs.order_status,
    fhs.status_history,
    dr.sk_region,
    dr.name AS region,
    dr.city_name,
    dr.city_group
from daily_published_listings fhs
join datalake_clean.ods_sale_fact_listing_flows lf 
    on cast(lf.sk_house_listing as bigint) / 1000 = fhs.id_house
join datalake_clean.ods_dim_region dr
    on dr.sk_region = lf.sk_region
where fhs.order_status = 1
)
select
    date,
    weekday_name,
    week_start,
    sk_region,
    region,
    city_name,
    city_group,
    count(distinct id_house) as ongoing_listings
from daily_published_listings_with_region
group by 1, 2, 3, 4 ,5, 6, 7
