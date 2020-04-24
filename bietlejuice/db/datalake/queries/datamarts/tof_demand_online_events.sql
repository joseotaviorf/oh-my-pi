with
last_version_listings as (
	select 
		id_house,
		sk_house_listing,
		cast(nullif(ts_listing_version_start,'') as timestamp) as ts_listing_version_start,
		cast(nullif(ts_listing_version_end,'') as timestamp) as ts_listing_version_end 
	from datalake_clean.ods_dim_house_listing 
	where cast(nullif(version,'') as bigint) > 0
)
, taxonomy_demand as (
	with taxonomy_min_ids as (
		select
		  min(id) as id
		from datalake_raw.gsheets_taxonomy_demand
		group by
			lower(app_type),
			lower(utm_source),
			lower(utm_medium),
			lower(branded),
			lower(first_update_source),
		        flg_via_reschedule
	)
	 select
	    cast(td.id as bigint) as id,
		td.app_type,
		td.utm_source,
		td.utm_medium,
		td.branded,
		td.first_update_source,
		cast(td.flg_via_reschedule as boolean) flg_via_reschedule ,
		td.Category as mkt_category,
		td.Flow as mkt_flow,
		td.Completion as mkt_completion,
		td.Channel as mkt_channel,
		td.Medium as mkt_medium,
		td.Origin as mkt_origin,
		td.Source as mkt_source,
		td.Platform as mkt_platform
	from datalake_raw.gsheets_taxonomy_demand td
	join taxonomy_min_ids td_min
		on td.id = td_min.id
)
, base as (
select
    cast(date_trunc('week',date(ts_event)) as varchar) as event_week,
    cast(date(ts_event) as varchar) as event_date,
	cast(ts_event as varchar) as event_timestamp,
	ev.id_user,
	ev.id_amplitude,
	trim(json_extract_scalar(event_properties, '$["house_id"]')) as house_id,
	lvl.sk_house_listing,
	cast(json_extract_scalar(event_properties, '$.agent_id') as bigint) as agent_id,
	case when trim(event_type) = 'listing_page_viewed' then 1 else 0 end as listing_page_viewed,
	case when trim(event_type) = 'pilot_cw_button_clicked' then 1 else 0 end as talk_to_agent_button_clicked,
	case when trim(event_type) = 'piloto_cw_dialog_viewed' then 1 else 0 end as talk_to_agent_dialog_viewed, 
	case when trim(event_type) = 'piloto_cw_message_sent' then 1 else 0 end as talk_to_agent_message_sent,
    case when trim(event_type) = 'piloto_cw_message_sent' then substr(regexp_extract(replace(regexp_replace(json_extract_scalar(event_properties, '$["message_content"]'),'\n',' '),'''',' '),'(?<=(([0-9]{{9}}))).*'),4) else null end as talk_to_agent_message_content,
	case when trim(event_type) = 'offer_submitted' then 1 else 0 end as offer_submitted,
    cast(json_extract_scalar(user_properties, '$.utm_source') as varchar) as utm_source,
	cast(json_extract_scalar(user_properties, '$.utm_medium') as varchar) as utm_medium,
	cast(json_extract_scalar(user_properties, '$.utm_campaign') as varchar) as utm_campaign,
	cast(json_extract_scalar(user_properties, '$.utm_content') as varchar) as utm_content, 
	cast(json_extract_scalar(user_properties, '$.utm_term') as varchar) as utm_term,
	case when UPPER(cast(json_extract_scalar(user_properties, '$.utm_campaign') as varchar)) like '%BRANDED%' or UPPER(cast(json_extract_scalar(user_properties, '$.utm_campaign') as varchar)) like '%INSTITUCIONAL%' then 'Branded' else 'Outro' end as branded,
	cast(json_extract_scalar(user_properties , '$.platform') as varchar) as app_type
from datalake_amplitude_clean_prod.events ev
left join last_version_listings lvl
  	on trim(json_extract_scalar(ev.event_properties, '$["house_id"]'))  = lvl.id_house
  	and ts_event between ts_listing_version_start and (coalesce(ts_listing_version_end,current_timestamp) - interval '1' second)
where date(ts_event) >= date('2020-03-18') and (event_type = 'offer_submitted' OR event_type like '%cw%' or event_type = 'listing_page_viewed')
)
select 
	b.event_week,
	b.event_date,
	b.event_timestamp,
	b.id_user,
	b.id_amplitude,
	b.house_id,
	b.sk_house_listing,
	b.agent_id,
	b.offer_submitted,
	b.listing_page_viewed,
	b.talk_to_agent_button_clicked,
	b.talk_to_agent_dialog_viewed,
	b.talk_to_agent_message_sent,
	b.talk_to_agent_message_content,
	b.utm_source,
	b.utm_medium,
	b.utm_campaign,
	b.utm_content,
	b.utm_term,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_category end as mkt_category,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_flow end as mkt_flow,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_completion end as mkt_completion,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_origin end as mkt_origin,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_channel end as mkt_channel,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_medium end as mkt_medium,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_source end as mkt_source,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_platform end as mkt_platform
from base b
left join taxonomy_demand td 
	on lower(coalesce(td.app_type,'')) = lower(coalesce(b.app_type,''))
	and lower(coalesce(td.utm_source,'')) = lower(coalesce(b.utm_source,''))
	and lower(coalesce(td.utm_medium,'')) = lower(coalesce(b.utm_medium,''))
	and lower(coalesce(td.branded,'')) = lower(coalesce(b.branded,''))
