-- Completed Talk to Agent accounting from Bookings (mainly before 2020/05/20)
with bookings_agent_tenant as(

    select 
        cast(rf.sk_user_agent as integer) as agent,
        cast(rf.sk_client as integer) as tenant,
        cast(db.id_property as integer) as house,
        count(distinct db.sk_booking) as bookings_by_agent,
        min(db.dt_created) as first_agent_booking_ts
        
    from datalake_clean.ods_fact_listing_rent_flows rf
    join datalake_clean.ods_dim_booking db
        on rf.sk_booking = cast(db.sk_booking  as varchar)
        
    where db.dt_created > '2020-03-01' --After feature has started
        and db.first_update_source='Corretores' --Bookings created by Agents
        and date_trunc('day',cast(db.dt_created as timestamp))=date_trunc('day',cast(db.dt_scheduling as timestamp)) --Bookings registered by Agents = they have the same created and scheduling day
    
    group by 1,2,3 -- Only count one attendance for the triple agent-tenant-house
),


-- Max version of QuintoAndar's listings
max_version as (
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
    join max_version m
        on cast(h.sk_house_listing as bigint) = cast(m.sk_house_listing as bigint)
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
    select 
        distinct substr(r.sk_house_listing,1,9) as sk_house_listing,
        region_code
    from datalake_clean.ods_fact_house_listing_flows r
    left join datalake_clean.ods_dim_region using(sk_region)
),

-- Sales Agents (this determines business context)
sales_agents as(
    select distinct id_agent,
        cast(u.id as integer) as id
    from datalake_ebdb_clean_prod.booking a 
    join datalake_clean.ods_dim_user u
        on id_agent = cast(nullif(u.dados_agente_id,'') as bigint)
    where a.business_context = 'SALE'
        and id_agent is not null
),

-- Events (current registry for every Talk to Agent started)
events as(
    select 
        cast(json_extract_scalar(event_properties, '$["house_id"]') as integer) as house_id,
        cast(json_extract_scalar(event_properties, '$["agent_id"]') as integer) as agent_id,
        cast(json_extract_scalar(event_properties, '$["tenant_id"]') as integer) as tenant_id,
        min(nullif(substr(cast(ts_event as varchar),1,19),'')) as first_message_ts,
        array_join(array_agg(trim(substr(regexp_extract(replace(regexp_replace(json_extract_scalar(event_properties, '$["message_content"]'),'\n',' '),'''',' '),'(?<=(([0-9]{9}))).*'),3))),' + ') as message,
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
     t.first_attendance_ts

from events e

left join talk_to_agent_completed t
    on t.tenant=e.tenant_id
    and t.agent=e.agent_id
    and t.house=e.house_id
    
left join datalake_clean.ods_dim_user u
    on cast(nullif(u.id,'') as integer)=e.tenant_id

left join house_properties h 
    on cast(h.sk_house_listing as integer) = e.house_id

left join sales_agents sa
    on sa.id=e.agent_id

left join max_version m
    on e.house_id = m.id_house

)
    

select * from final
order by first_message_ts desc
