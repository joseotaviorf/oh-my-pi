with
taxonomy_demand as (
	with taxonomy_min_ids as (
		select
		  min(id) as id
		from datalake_gsheets_clean_prod.taxonomy_demand
		where first_update_source = 'Inquilinos'
		    and CAST(flg_via_reschedule AS VARCHAR) = '0'
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
	from datalake_gsheets_clean_prod.taxonomy_demand td
	join taxonomy_min_ids td_min
		on td.id = td_min.id
),

tta_taxonomy as (
    WITH
    tta_raw as (
        SELECT DISTINCT
            COALESCE(INTEGER(ep_id_house), -1) AS house,
            COALESCE(INTEGER(ep_id_agent), -1) AS agent,
            COALESCE(INTEGER(id_user), -1) AS tenant,
            up_utm_source AS utm_source,
            up_utm_medium AS utm_medium,
            up_utm_campaign AS utm_campaign,
            up_utm_term AS utm_term,
            up_utm_content AS utm_content,
            CASE
                WHEN
                    (LOWER(up_utm_campaign) LIKE '%branded%' OR LOWER(up_utm_campaign) LIKE '%institucional%')
                    AND LOWER(up_utm_campaign) NOT LIKE '%non-branded%'
                THEN 'Branded'
                ELSE 'Outro'
            END AS branded,
            up_app_type AS app_type,
            TIMESTAMP(ts_event) AS event_timestamp
        FROM
            datalake_amplitude_clean_prod.170698_piloto_cw_message_sent_events
        WHERE
            ts_event > TIMESTAMP('2020-03-01 00:00')
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
        min(CAST(db.dt_created AS varchar)) as first_agent_booking_ts

    from datalake_clean.ods_dim_booking db
    left join datalake_clean.ods_dim_user u
        on id_agent=CAST(u.dados_agente_id AS BIGINT)

    where db.dt_created > DATE('2020-03-01') --After feature has started
        and db.first_update_source='Corretores' --Bookings created by Agents

        and u.id IS NOT NULL
        and id_visitor IS NOT NULL
        and id_property IS NOT NULL

        --considering also "Agendamentos" when the Agent schedule a Visit
        --and date_trunc('day',cast(db.dt_created as timestamp))=date_trunc('day',cast(db.dt_scheduling as timestamp)) --Bookings registered by Agents = they have the same created and scheduling day

    group by 1,2,3 -- Only count one attendance for the triple agent-tenant-house
),

-- Filter one version per listing
listing as (
    select cast(id_house as bigint) as id_house,
        cast(max(sk_house_listing) as bigint) as sk_house_listing
    from datalake_clean.ods_dim_house_listing
    where cast(sk_house_listing as varchar) > ''
        and cast(id_house as varchar) > ''
    group by 1),

-- Completed Talk to Agent accounting from AgentSupport (mainly after 2020/05/20)
registered_tta as (
    select
        cast(u.id as integer) as agent,
        cast(a.id_user as integer) as tenant,
        cast(h.id_house as integer) as house,
        count(*) as attendances_by_agent,
        substr(cast(min(a.ts_created) as varchar),1,19) as first_agent_attendance_ts
    from datalake_ebdb_clean_prod.agent_support a --this one is not on clean yet
    join datalake_ebdb_clean_prod.listing_business_context bc
        on bc.id = a.id_listing
    join datalake_clean.ods_dim_house_listing h
        on bc.id_house = cast(h.id_house as bigint)
    join datalake_clean.ods_dim_user u
        on cast(u.dados_agente_id as bigint) = a.id_agent
    join listing l
        on cast(h.sk_house_listing as bigint) = cast(l.sk_house_listing as bigint)
    where cast(h.id_house as varchar) > ''
        and u.dados_agente_id IS NOT NULL
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
        on cast(r.id as bigint)=h.id_region
),

-- Events (current registry for every Talk to Agent started)
events as(
    SELECT
        COALESCE(INTEGER(ep_id_house), -1) AS house_id,
        COALESCE(INTEGER(ep_id_agent), -1) AS agent_id,
        COALESCE(INTEGER(id_user), -1) AS tenant_id,
        MIN(ts_event) as first_message_ts,
        ARRAY_JOIN(ARRAY_AGG(REPLACE(TRIM(SUBSTR(REGEXP_EXTRACT(REPLACE(REGEXP_REPLACE(ep_message_content,'\n',' '),'''',' '),'(?<=(([0-9]{9}))).*'),3)), 'omprar.', '')),' + ') as message,
        COUNT(*) as count_messages
    FROM
        datalake_amplitude_clean_prod.170698_piloto_cw_message_sent_events
    WHERE
        ts_event > TIMESTAMP('2020-03-01 00:00')
    GROUP BY 1,2,3
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
    on u.id=e.tenant_id

left join house_properties h
    on cast(h.sk_house_listing as integer) = e.house_id

-- identifies the agent context with the booleans columns in user dimension: is_sale_agent
left join datalake_clean.ods_dim_user sa
    on CAST(e.agent_id AS INTEGER) = cast(sa.id as integer)
    and sa.is_sale_agent

-- version of the moment the tenant has sent the message
join datalake_clean.ods_dim_house_listing m
    on e.house_id = cast(nullif(cast(m.id_house as varchar),'') as bigint)
    and cast(ts_listing_version_start as varchar) <  e.first_message_ts
    and (cast(ts_listing_version_end as varchar)='' or cast(ts_listing_version_end as varchar) > e.first_message_ts)

-- marketing taxonomy
join tta_taxonomy mkt
    on mkt.tenant = coalesce(e.tenant_id, -1)
    and mkt.agent = coalesce(e.agent_id, -1)
    and mkt.house = coalesce(e.house_id, -1)
    and event_order = 1

)


-- validator
--select count(*) as total_tta, count(case when attended=true then 1 end) as total_attended, count(case when bookings_by_agent>0 then 1 end) as bookings_by_agent,count(case when attendances_by_agent>0 then 1 end) as attendances_by_agent  from final

select
    CAST(agent_id AS VARCHAR) AS agent_id,
    CAST(tenant_id AS VARCHAR) AS tenant_id,
    CAST(house_id AS VARCHAR) AS house_id,
    CAST(sk_house_listing AS VARCHAR) AS sk_house_listing,
    CAST(attended AS VARCHAR) AS attended,
    CAST(message AS VARCHAR) AS message,
    CAST(tenant_name AS VARCHAR) AS tenant_name,
    CAST(tenant_phone AS VARCHAR) AS tenant_phone,
    CAST(tenant_email AS VARCHAR) AS tenant_email,
    CAST(msg_sent AS VARCHAR) AS msg_sent,
    CAST(delta_hours_elapsed AS VARCHAR) AS delta_hours_elapsed,
    CAST(delta_hours_attended AS VARCHAR) AS delta_hours_attended,
    CAST(region_code AS VARCHAR) AS region_code,
    CAST(business_context AS VARCHAR) AS business_context,
    CAST(first_message_ts AS VARCHAR) AS first_message_ts,
    CAST(bookings_by_agent AS VARCHAR) AS bookings_by_agent,
    CAST(attendances_by_agent AS VARCHAR) AS attendances_by_agent,
    CAST(first_attendance_ts AS VARCHAR) AS first_attendance_ts,
    CAST(app_type AS VARCHAR) AS app_type,
    CAST(utm_source AS VARCHAR) AS utm_source,
    CAST(utm_medium AS VARCHAR) AS utm_medium,
    CAST(branded AS VARCHAR) AS branded,
    CAST(mkt_category AS VARCHAR) AS mkt_category,
    CAST(mkt_flow AS VARCHAR) AS mkt_flow,
    CAST(mkt_completion AS VARCHAR) AS mkt_completion,
    CAST(mkt_origin AS VARCHAR) AS mkt_origin,
    CAST(mkt_channel AS VARCHAR) AS mkt_channel,
    CAST(mkt_medium AS VARCHAR) AS mkt_medium,
    CAST(mkt_source AS VARCHAR) AS mkt_source,
    CAST(mkt_platform AS VARCHAR) AS mkt_platform,
    CAST(utm_campaign AS VARCHAR) AS utm_campaign,
    CAST(utm_term AS VARCHAR) AS utm_term,
    CAST(utm_content AS VARCHAR) AS utm_content,
    CAST(NOW() AS VARCHAR) AS ts_load
from 
    final 
order by first_message_ts desc
