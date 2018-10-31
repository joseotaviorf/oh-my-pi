with views as (
	select
	 e_house_id as imovel_id,
	 amplitude_id as user_id,
	 cast(date_trunc('week',cast(regexp_extract(event_time, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp)) as date) as dt_view
	from
	 datalake_clean.amplitude_events ae
	where et = 'listing_page_viewed'
	and trim(app) = '170698'
),
unique_viewers as (
	select
		count(distinct(user_id)) as unique_viewers,
		imovel_id,
		dt_view
	from
		views
	group by imovel_id, dt_view
)
select distinct
	coalesce(p.sk_house_listing, concat(v.imovel_id,'001')) as sk_house_listing,
	count(1) over (partition by v.imovel_id, v.dt_view) as total_views,
	uv.unique_viewers,
	v.dt_view
from
	views v
left join
	unique_viewers uv
	on uv.imovel_id = v.imovel_id
	and uv.dt_view = v.dt_view
left join
	datalake_clean.ods_dim_house_listing p
	on trim(p.id_house) = v.imovel_id
	and coalesce(cast(cast(regexp_extract(p.ts_listing_version_start, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as date),date('1900-01-01')) <= v.dt_view
	and coalesce(cast(cast(regexp_extract(p.ts_listing_version_end, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as date),date('2300-01-01')) >= v.dt_view