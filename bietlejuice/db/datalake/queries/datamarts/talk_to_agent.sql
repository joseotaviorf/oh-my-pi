with
taxonomy_demand as (
	with taxonomy_min_ids as (
		select
		  min(id) as id
		from datalake_raw.gsheets_taxonomy_demand
		where first_update_source = 'Inquilinos'
		    and flg_via_reschedule = '0'
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
),

tta_taxonomy as (
    WITH
    tta_raw as (
        select distinct
	        coalesce(cast(json_extract_scalar(event_properties, '$["house_id"]') as integer), -1) as house,
	        coalesce(cast(json_extract_scalar(event_properties, '$["agent_id"]') as integer), -1) as agent,
        	coalesce(cast(evt.id_user as integer), -1) as tenant,
            json_extract_scalar(user_properties, '$["utm_source"]') as utm_source,
        	json_extract_scalar(user_properties, '$["utm_medium"]') as utm_medium,
        	json_extract_scalar(user_properties, '$["utm_campaign"]') as utm_campaign,
        	json_extract_scalar(user_properties, '$["utm_term"]') as utm_term,
        	json_extract_scalar(user_properties, '$["utm_content"]') as utm_content,
        	case when (UPPER(json_extract_scalar(user_properties, '$["utm_campaign"]')) like '%BRANDED%'
        					or UPPER(json_extract_scalar(user_properties, '$["utm_campaign"]')) like '%INSTITUCIONAL%')
        					and UPPER(json_extract_scalar(user_properties, '$["utm_campaign"]')) not like '%NON-BRANDED%'
        		 then 'Branded'
        		 else 'Outro'
        	end as branded,
        	json_extract_scalar(user_properties , '$["platform"]') as app_type,
            cast(ts_event as timestamp) as event_timestamp
        from datalake_amplitude_clean_prod.events evt
    	where event_type = 'piloto_cw_message_sent'
			and ts_event > timestamp '2020-03-01 00:00'
    )
    select
        tta.house,
        tta.tenant,
        tta.agent,
        tta.app_type,
        tta.utm_source,
        tta.utm_medium,
        tta.branded,
        td.mkt_category,
        td.mkt_flow,
        td.mkt_completion,
        td.mkt_origin,
    	td.mkt_channel,
    	td.mkt_medium,
    	td.mkt_source,
    	td.mkt_platform,
    	tta.utm_campaign,
    	tta.utm_term,
    	tta.utm_content,
    	tta.event_timestamp,
    	row_number() over(
    					partition by tta.house, tta.tenant, tta.agent
						order by event_timestamp
						) as event_order
    from tta_raw tta
    left join taxonomy_demand td
        on lower(coalesce(td.app_type,'')) = lower(coalesce(tta.app_type,''))
    	and lower(coalesce(td.utm_source,'')) = lower(coalesce(tta.utm_source,''))
    	and lower(coalesce(td.utm_medium,'')) = lower(coalesce(tta.utm_medium,''))
    	and lower(coalesce(td.branded,'')) = lower(coalesce(tta.branded,''))
),

-- Completed Talk to Agent accounting from Bookings (mainly before 2020/05/20)
bookings_agent_tenant as(

    select
        cast(u.id as integer) as agent,
        cast(id_visitor as integer) as tenant,
        cast(id_property as integer) as house,
        count(distinct db.sk_booking) as bookings_by_agent,
        min(db.dt_created) as first_agent_booking_ts

    from datalake_clean.ods_dim_booking db
    left join datalake_clean.ods_dim_user u
        on id_agent=u.dados_agente_id

    where db.dt_created > '2020-03-01' --After feature has started
        and db.first_update_source='Corretores' --Bookings created by Agents

        and u.id <> ''
        and id_visitor <> ''
        and id_property <> ''

        --considering also "Agendamentos" when the Agent schedule a Visit
        --and date_trunc('day',cast(db.dt_created as timestamp))=date_trunc('day',cast(db.dt_scheduling as timestamp)) --Bookings registered by Agents = they have the same created and scheduling day

    group by 1,2,3 -- Only count one attendance for the triple agent-tenant-house
),

-- Filter one version per listing
listing as (
    select cast(id_house as bigint) as id_house,
        cast(max(sk_house_listing) as bigint) as sk_house_listing
    from datalake_clean.ods_dim_house_listing
    where sk_house_listing > ''
        and id_house > ''
    group by 1),

-- Completed Talk to Agent accounting from AgentSupport (mainly after 2020/05/20)
registered_tta as (
    select
        cast(u.id as integer) as agent,
        cast(a.user_id as integer) as tenant,
        cast(h.id_house as integer) as house,
        count(*) as attendances_by_agent,
        substr(cast(cast(from_iso8601_timestamp(min(a.created_at)) as timestamp) as varchar),1,19) as first_agent_attendance_ts

    from datalake_ebdb_raw_prod.AgentSupport a --this one is not on clean yet
    join datalake_ebdb_clean_prod.listing_business_context bc
        on bc.id = a.listing_id
    join datalake_clean.ods_dim_house_listing h
        on bc.id_house = cast(h.id_house as bigint)
    join datalake_clean.ods_dim_user u
        on cast(u.dados_agente_id as bigint) = a.agent_id
    join listing l
        on cast(h.sk_house_listing as bigint) = cast(l.sk_house_listing as bigint)
    where h.id_house > ''
        and u.dados_agente_id > ''
        and a.status = 'COMPLETE' --here at this stage of Prod. Dev. we want to account only for Completed Talk to Agents
    group by 1,2,3 -- Only count one attendance for the triple agent-tenant-house
),


-- Completed Talk to Agent (everything)
talk_to_agent_completed as (

    select
        coalesce(b.agent,t.agent) as agent,
        coalesce(b.tenant,t.tenant) as tenant,
        coalesce(b.house,t.house) as house,

        max(b.bookings_by_agent) as bookings_by_agent,
        max(t.attendances_by_agent) as attendances_by_agent,

        min(coalesce(b.first_agent_booking_ts,t.first_agent_attendance_ts)) as first_attendance_ts,

        min(b.first_agent_booking_ts) as first_agent_booking_ts,
        min(t.first_agent_attendance_ts) as first_agent_attendance_ts

    from bookings_agent_tenant b
    full outer join registered_tta t
        on b.agent=t.agent
        and b.tenant=t.tenant
        and b.house=t.house

    group by 1,2,3
),

--Listing region code
house_properties as(
    select h.id as sk_house_listing,
        r.region_code
    from datalake_ebdb_clean_prod.house h
    left join datalake_clean.ods_dim_region r
        on cast(nullif(r.id,'') as bigint)=h.id_region
),

-- Events (current registry for every Talk to Agent started)
events as(
    select
        cast(json_extract_scalar(event_properties, '$["house_id"]') as integer) as house_id,
        cast(json_extract_scalar(event_properties, '$["agent_id"]') as integer) as agent_id,
        cast(id_user as integer) as tenant_id,
        min(nullif(substr(cast(ts_event as varchar),1,19),'')) as first_message_ts,
        array_join(array_agg(replace(trim(substr(regexp_extract(replace(regexp_replace(json_extract_scalar(event_properties, '$["message_content"]'),'\n',' '),'''',' '),'(?<=(([0-9]{9}))).*'),3)), 'omprar.', '')),' + ') as message,
        count(*) as count_messages

    from datalake_amplitude_clean_prod.events
    where event_type = 'piloto_cw_message_sent'

        and ts_event > timestamp '2020-03-01 00:00'

    group by 1,2,3
),

--putting everything together
final as(

select
    e.agent_id,
    e.tenant_id,
    e.house_id,
    m.sk_house_listing,
    case when t.first_attendance_ts is null then false else true end as attended,
    e.message,
    u.nome as tenant_name,
    u.telefone_principal as tenant_phone,
    u.email as tenant_email,
    count_messages as msg_sent,

    case when t.first_attendance_ts is null then 1.00*date_diff('minute',cast(e.first_message_ts as timestamp),date_add('hour',-3,current_timestamp))/60 end as delta_hours_elapsed,
    case when t.first_attendance_ts is not null then 1.00*date_diff('minute',cast(e.first_message_ts as timestamp),cast(t.first_attendance_ts as timestamp))/60 else null end as delta_hours_attended,

    h.region_code,

    case when sa.id is null then 'RENT' else 'SALE' end as business_context,

    e.first_message_ts,
    t.bookings_by_agent,
    t.attendances_by_agent,
    t.first_attendance_ts,

    coalesce(mkt.app_type, '') as app_type,
	coalesce(mkt.utm_source, '') as utm_source,
	coalesce(mkt.utm_medium, '') as utm_medium,
	coalesce(mkt.branded, '') as branded,
	coalesce(mkt.mkt_category, 'Not Mapped') as mkt_category,
	coalesce(mkt.mkt_flow, 'Not Mapped') as mkt_flow,
	coalesce(mkt.mkt_completion, 'Not Mapped') as mkt_completion,
	coalesce(mkt.mkt_origin, 'Not Mapped') as mkt_origin,
	coalesce(mkt.mkt_channel, 'Not Mapped') as mkt_channel,
	coalesce(mkt.mkt_medium, 'Not Mapped') as mkt_medium,
	coalesce(mkt.mkt_source, 'Not Mapped') as mkt_source,
	coalesce(mkt.mkt_platform, 'Not Mapped') as mkt_platform,
	coalesce(mkt.utm_campaign, '') as utm_campaign,
	coalesce(mkt.utm_term, '') as utm_term,
	coalesce(mkt.utm_content, '') as utm_content

from events e

left join talk_to_agent_completed t
    on t.tenant=e.tenant_id
    and t.agent=e.agent_id
    and t.house=e.house_id

left join datalake_clean.ods_dim_user u
    on cast(nullif(u.id,'') as integer)=e.tenant_id

left join house_properties h
    on cast(h.sk_house_listing as integer) = e.house_id

-- identifies the agent context with the booleans columns in user dimension: is_sale_agent
left join datalake_clean.ods_dim_user sa
    on e.agent_id = cast(sa.id as integer)
    and sa.is_sale_agent = 'True'

-- version of the moment the tenant has sent the message
join datalake_clean.ods_dim_house_listing m
    on e.house_id = cast(nullif(m.id_house,'') as bigint)
    and ts_listing_version_start <  e.first_message_ts
    and (ts_listing_version_end='' or ts_listing_version_end > e.first_message_ts)

-- marketing taxonomy
join tta_taxonomy mkt
    on mkt.tenant = coalesce(e.tenant_id, -1)
    and mkt.agent = coalesce(e.agent_id, -1)
    and mkt.house = coalesce(e.house_id, -1)
    and event_order = 1

)


-- validator
--select count(*) as total_tta, count(case when attended=true then 1 end) as total_attended, count(case when bookings_by_agent>0 then 1 end) as bookings_by_agent,count(case when attendances_by_agent>0 then 1 end) as attendances_by_agent  from final

select * from final order by first_message_ts desc
