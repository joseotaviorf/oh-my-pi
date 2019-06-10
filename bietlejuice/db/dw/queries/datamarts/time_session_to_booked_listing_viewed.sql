with house_status as (
	-- merging of redundant house status records (subsequent status without sk_max_status_date, reasoned by minor status changes < 1 day)
	select
		fhs.sk_house,
		fhs.sk_region,
		fhs.status_history as status,
		min(fhs.sk_min_status_date) as sk_min_status_date,
		coalesce(to_char(to_date(fhs.sk_max_status_date, 'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, to_char(current_date - 1, 'YYYYMMDD')::bigint) as sk_max_status_date
	from fact_house_status fhs
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
	where dd.date > date('2019-01-01')
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
	    dr.macro_name as macro_region,
	    dr.name as neighborhood,
	    date(date_trunc('week', dhl.ts_publication)) as week_start_publication,
	    case when dhl.house_bedrooms in (0,1) then 1
	     	 when dhl.house_bedrooms = 2 then 2
	     	 when dhl.house_bedrooms = 3 then 3
	     	 when dhl.house_bedrooms >= 4 then 4
	   	end as house_bedrooms,
		dhl.is_b2b,
		-- new dimensions
 		dhl.house_rent,
		dhl.house_total_value,
		dhl.house_total_area
	from house_status_per_day hsd
	join dim_region dr on dr.sk_region = hsd.sk_region
	join dim_house_listing dhl on hsd.sk_house = dhl.sk_house_listing
),
user_session_events as (
	-- returns top amplitude events that we use as proxy for session start, listing view and booking confirmation
	select
	amplitude_id,
	to_char(to_date(regexp_substr(event_time, '(\\d{4}-\\d{2}-\\d{2})'), 'YYYY-MM-DD'), 'YYYYMMDD')::bigint as sk_event_dt,
	regexp_substr(event_time, '(\\d{4}-\\d{2}-\\d{2})')::date as event_dt,
	regexp_substr(event_time, '(\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2})', 1)::timestamp as event_ts,
	session_id,
	et,
	case when regexp_substr(e_house_id, '^\\d{9}$') != ''
		 then regexp_substr(e_house_id, '^\\d{9}$')::bigint
		 else null end as id_house
	from datalake_clean.amplitude_events evt
	where evt.et in ('listing_page_viewed', 'search_results_page_viewed', 'home_page_viewed', 'visit_schedule_confirmed')
	and ym >= '2019-01'
	and app = '170698'
),
user_session_mapping as (
	-- returns min event timestamps for different partitions like user, session and house id
	select distinct
	amplitude_id,
	session_id,
	id_house,
	min(event_ts) over(partition by amplitude_id, session_id) as ts_session_start,
	min(case when et='listing_page_viewed' then event_ts end) over(partition by amplitude_id, session_id, id_house) as ts_first_lpv_session,
	min(case when et='visit_schedule_confirmed' then event_ts end) over(partition by amplitude_id, id_house) as ts_visit_schedule_confirmed,
	min(case when et='search_results_page_viewed' then event_ts end) over(partition by amplitude_id, session_id) as ts_first_search_session
	from user_session_events use
),
house_conversion_sessions as (
	-- returns timestamps per user and house id for activities that resulted in a booking
 	select
	amplitude_id,
	id_house,
	to_char(min(ts_visit_schedule_confirmed)::date, 'YYYYMMDD')::bigint as sk_booking_dt,
	min(ts_session_start) as ts_session_start,
	min(ts_first_lpv_session) as ts_first_lpv_session,
	min(ts_visit_schedule_confirmed) as ts_visit_schedule_confirmed,
	min(ts_first_search_session) as ts_first_search_session
	from user_session_mapping usm
	where id_house is not null
	group by 1, 2
    having min(ts_visit_schedule_confirmed) is not null
),
results_raw as (
	-- returns amplitude event conversion timestamps with all dimensions of the related house id
	select distinct
		hsd.city_group,
		hsd.city,
		hsd.macro_region,
		hsd.neighborhood,
		hsd.week_start,
		hsd.week_start_publication,
		hsd.house_bedrooms,
		hsd.is_b2b,
		hsd.house_rent,
		hsd.house_total_value,
		hsd.house_total_area,
		hcs.amplitude_id,
		hcs.id_house,
		hcs.sk_booking_dt,
		hcs.ts_session_start,
		hcs.ts_first_lpv_session,
		hcs.ts_visit_schedule_confirmed,
		hcs.ts_first_search_session,
		date_diff('second', ts_session_start, ts_first_lpv_session) as seconds_sessionstart_to_first_lpv,
		coalesce(hcs.ts_first_search_session < hcs.ts_first_lpv_session, false) as searched_in_session_before_lpv
	from house_conversion_sessions hcs
	join house_status_and_dimensions hsd on hsd.id_house = hcs.id_house and hsd.sk_date = hcs.sk_booking_dt
)
select * from results_raw;