/* considerations:
 * bookings sem listing_page views are excluded 4400/96800 casos no Jun19
 * contamos como sessions so aquelas que tem por menos um listing_page_view event de qualquer imovel
 */
with house_status as (
/* merging of redundant house status records (subsequent status without sk_max_status_date, reasoned by minor status changes < 1 day) */
	select
		fhs.sk_house_listing as sk_house,
		fhs.sk_region,
		fhs.status_history as status,
		min(nullif(fhs.sk_status_start_date,-1)) as sk_min_status_date,
		coalesce(to_char(to_date(nullif(fhs.sk_status_end_date,-1), 'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, to_char(current_date - 1, 'YYYYMMDD')::bigint) as sk_max_status_date
	from fact_house_listing_status fhs
	where fhs.status_history = 'publicado'
	group by 1, 2, 3, 5
),
house_status_per_day as (
/* create date series for each house and day in status publication
 * ongoing listings = week_day = 0 (sunday)
 * use daily status to filter listing_page_views that occured on not publicated listings (product/tracking bug)
 */
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
	where dd.date > date('2018-06-01')
),
house_status_and_dimensions as (
/* returns all breakdowns for all listing versions for each day in publication */
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
 		dhl.house_rent,
		dhl.house_total_value,
		dhl.house_total_area
	from house_status_per_day hsd
	join dim_region dr on dr.sk_region = hsd.sk_region
	join dim_house_listing dhl on hsd.sk_house = dhl.sk_house_listing
),
user_listing_page_views as (
/*
 * returns for each amplitude_id and house_id first listing_page_view ts, first visit_schedule_confirmed ts and user_id
 * must have listing_page_view
 * must have visit_schedule_confirmed
 * listing_page_view must have happened before visit_schedule_confirmed
 */
    with user_session_events as (
        /* returns top amplitude events that we use as proxy for session start, listing view and booking confirmation */
            SELECT
                amplitude_id::varchar,
                case when nullif(regexp_substr(user_id::varchar, '^\\d+$'), '') is not null
                     then regexp_substr(user_id::varchar, '^\\d+$')::bigint
                     else null end as user_id,
                regexp_substr(event_time, '(\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2})', 1)::timestamp as event_ts,
                session_id::varchar,
                event_type,
                case when nullif(regexp_substr(cast(json_extract_path_text(event_properties, 'house_id') as varchar), '^\\d{9}$'), '') is not null
                     then regexp_substr(cast(json_extract_path_text(event_properties, 'house_id') as varchar), '^\\d{9}$')::bigint
                     else null end as id_house
           FROM datalake_amplitude_clean_prod.events
           WHERE event_type IN ('listing_page_viewed', 'search_results_page_viewed', 'home_page_viewed', 'visit_schedule_confirmed')
                AND app = 170698
                AND coalesce(session_id, -1) <> -1
    )
	select
		amplitude_id,
		id_house,
		min(case when et='visit_schedule_confirmed' then user_id end) as user_id,
		min(case when et='listing_page_viewed' then event_ts end) as ts_first_listing_page_view,
		min(case when et='visit_schedule_confirmed' then event_ts end) as ts_first_visit_schedule_confirmed
	from user_session_events
	where et in ('listing_page_viewed', 'visit_schedule_confirmed')
	and id_house is not null
	group by 1, 2 having min(case when et='listing_page_viewed' then event_ts end) < min(case when et='visit_schedule_confirmed' then event_ts end)
),
user_sessions as (
/* returns for each amplitude_id the sessions and their start timestamps */
    with user_session_events as (
        /* returns top amplitude events that we use as proxy for session start, listing view and booking confirmation */
            -- enriching with amplitude data via SPARK
            SELECT
                amplitude_id::varchar,
                case when nullif(regexp_substr(user_id::varchar, '^\\d+$'), '') is not null
                     then regexp_substr(user_id::varchar, '^\\d+$')::bigint
                     else null end as user_id,
                regexp_substr(event_time, '(\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2})', 1)::timestamp as event_ts,
                session_id::varchar,
                event_type,
                case when nullif(regexp_substr(cast(json_extract_path_text(event_properties, 'house_id') as varchar), '^\\d{9}$'), '') is not null
                     then regexp_substr(cast(json_extract_path_text(event_properties, 'house_id') as varchar), '^\\d{9}$')::bigint
                     else null end as id_house
           FROM datalake_amplitude_clean_prod.events
           WHERE event_type IN ('listing_page_viewed', 'search_results_page_viewed', 'home_page_viewed', 'visit_schedule_confirmed')
                AND app = 170698
                AND coalesce(session_id, -1) <> -1
    )
	select
		amplitude_id,
		session_id,
		min(event_ts) as ts_session_start_proxy,
		to_char(min(event_ts), 'YYYYMMDD')::bigint as sk_dt_session_start_proxy
	from user_session_events use
	group by 1, 2
),
user_sessions_during_publication_enriched as (
/* returns for each amplitude_id / house / session pair the timestamp of first session after publication,
 * first listing view and first schedule confirmed with different house attributes
 * >> each line reflects one session during related house being in status publication */
	select distinct
		lpv.amplitude_id,
		lpv.id_house,
		min(sns.ts_session_start_proxy) over (partition by lpv.amplitude_id, lpv.id_house) as ts_first_session_pos_publ,
		sns.ts_session_start_proxy,
		lpv.ts_first_listing_page_view,
		lpv.ts_first_visit_schedule_confirmed,
		hsd.city_group,
		hsd.city,
		hsd.macro_region,
		hsd.neighborhood,
		hsd.house_bedrooms,
		hsd.is_b2b,
		hsd.house_rent,
		hsd.house_total_value,
		hsd.house_total_area,
		lpv.ts_first_visit_schedule_confirmed = min(lpv.ts_first_visit_schedule_confirmed) over (partition by lpv.amplitude_id) as is_users_first_booking,
		coalesce(lrf.sk_contract_signed_date, -1) > 0 as contract_signed
	from user_listing_page_views lpv
	join user_sessions sns on sns.amplitude_id = lpv.amplitude_id and sns.ts_session_start_proxy <= lpv.ts_first_listing_page_view
	join house_status_and_dimensions hsd on hsd.id_house = lpv.id_house and hsd.sk_date = sns.sk_dt_session_start_proxy
	left join fact_listing_rent_flows lrf on lrf.sk_house_listing/1000 = lpv.id_house and lrf.sk_client = lpv.user_id
)
select
	amplitude_id || id_house as fluxo_id,
	amplitude_id,
	id_house as house_id,
	ts_first_session_pos_publ,
	ts_first_listing_page_view,
	ts_first_visit_schedule_confirmed,
	is_users_first_booking,
	contract_signed,
	city_group,
	city,
	macro_region,
	neighborhood,
	house_bedrooms,
	is_b2b,
	house_rent,
	house_total_value,
	house_total_area,
	datediff(second,ts_first_session_pos_publ,ts_first_listing_page_view) as seconds_to_lpv,
	datediff(hour,ts_first_session_pos_publ,ts_first_listing_page_view) as hours_to_lpv,
	datediff(day,ts_first_session_pos_publ,ts_first_listing_page_view) as days_to_lpv,
	ntile(100) over(order by datediff(second, ts_first_session_pos_publ, ts_first_listing_page_view) asc) as pctl_all,
	ntile(100) over(partition by city_group order by datediff(second, ts_first_session_pos_publ, ts_first_listing_page_view) asc) as pctl_city_group,
	ntile(100) over(partition by is_users_first_booking order by datediff(second, ts_first_session_pos_publ, ts_first_listing_page_view) asc) as pctl_all_first_bk,
	ntile(100) over(partition by is_users_first_booking, city_group order by datediff(second, ts_first_session_pos_publ, ts_first_listing_page_view) asc) as pctl_all_first_bk_city_group
from user_sessions_during_publication_enriched
where ts_session_start_proxy = ts_first_session_pos_publ
;
