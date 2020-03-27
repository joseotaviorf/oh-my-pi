with
last_version_listings as (
select 
	id_house,
	sk_house_listing,
	cast(nullif(ts_listing_version_start,'') as timestamp) as ts_listing_version_start,
	cast(nullif(ts_listing_version_end,'') as timestamp) as ts_listing_version_end 
from datalake_clean.ods_dim_house_listing 
where cast(nullif(version,'') as bigint) > 0
),
houseagent as 
(
    with 
    houseagent_aud as (
                        select
                            from_unixtime(cast(timestamp as bigint)/1000) as date_time,
                            hou.*
                        from datalake_ebdb_raw_prod.houseagent_aud hou
                            join datalake_ebdb_raw_prod.usuariorevisionentity ure
                                on hou.rev = ure.id
    ),
    houseagent_status as (
                            select 
                                ia.house_id as id_house,
                                ia.date_time as started_timestamp,
                                lead(date_time) over(partition by house_id order by rev) as ended_timestamp,
                                agent_id
                            from houseagent_aud ia
    )
        select 
            cast(id_house as varchar) as id_house,
            date_format(started_timestamp, '%Y%m%d') as sk_start_date,
            date_format(ended_timestamp, '%Y%m%d') as sk_end_date,
            started_timestamp as ts_allocation_start,
            ended_timestamp as ts_allocation_end,
            agent_id
        from houseagent_status
)
select
    cast(date_trunc('week',date(ts_event)) as varchar) as event_week,
    cast(date(ts_event) as varchar) as event_date,
	cast(ts_event as varchar) as event_timestamp,
	ev.id_user,
	ev.id_amplitude,
	trim(json_extract_scalar(event_properties, '$["house_id"]')) as house_id,
	lvl.sk_house_listing,
	ha.agent_id,
	case when trim(event_type) = 'listing_page_viewed' then 1 else 0 end as listing_page_viewed,
	case when trim(event_type) = 'pilot_cw_button_clicked' then 1 else 0 end as button_clicked,
	case when trim(event_type) = 'piloto_cw_dialog_viewed' then 1 else 0 end as dialog_viewed, 
	case when trim(event_type) = 'piloto_cw_message_sent' then 1 else 0 end as message_sent,
    case when trim(event_type) = 'piloto_cw_message_sent' then substr(regexp_extract(replace(regexp_replace(json_extract_scalar(event_properties, '$["message_content"]'),'\n',' '),'''',' '),'(?<=(([0-9]{{9}}))).*'),4) else null end as talk_to_agent_message_content
from datalake_amplitude_clean_prod.events ev
left join last_version_listings lvl
  on trim(json_extract_scalar(ev.event_properties, '$["house_id"]'))  = lvl.id_house
  and ts_event between ts_listing_version_start and (coalesce(ts_listing_version_end,current_timestamp) - interval '1' second)
left join houseagent ha
  on trim(json_extract_scalar(ev.event_properties, '$["house_id"]'))  = ha.id_house
  and ts_event between ha.ts_allocation_start and (coalesce(ha.ts_allocation_end,current_timestamp) - interval '1' second)
  and trim(event_type) = 'piloto_cw_message_sent'
where (event_type like '%cw%' or event_type = 'listing_page_viewed') and date(ts_event) >= date('2020-03-18')
order by 1 desc, 2, 3, 4, 5, 6, 7, 8
